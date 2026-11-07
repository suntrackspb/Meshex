#!/usr/bin/env python3
"""Build a local STK-DRAFT-2 source from explicitly selected manifest directories.

Each --pack-dir contains manifest.json and media/<sha256>.(webp|png).
Manifest bytes are copied unchanged. The output must not exist. No uploads.
"""
import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import struct
import tempfile
from urllib.parse import urlsplit


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'Duplicate JSON key: {key}')
        result[key] = value
    return result


def invalid_constant(value):
    raise ValueError(f'Invalid JSON constant: {value}')


def validate_depth(value, depth=0):
    if depth > 64:
        raise ValueError('Sticker JSON is too deeply nested')
    if isinstance(value, dict):
        for child in value.values():
            validate_depth(child, depth + 1)
    elif isinstance(value, list):
        for child in value:
            validate_depth(child, depth + 1)


def text(value, limit, empty=False):
    if not isinstance(value, str) or len(value) > limit or (not empty and not value.strip()) or any(ord(c) < 32 or 127 <= ord(c) <= 159 for c in value):
        raise ValueError('Invalid text metadata')
    return value


def number(value, maximum):
    if type(value) is not int or not 0 < value <= maximum:
        raise ValueError('Invalid numeric metadata')
    return value


def source_url(value):
    uri = urlsplit(value)
    host = uri.hostname or ''
    if not re.fullmatch(r'https://[a-z0-9.-]+(?:/[A-Za-z0-9._~-]+)+', value) or len(value) > 128 or not value.endswith('/source.json') or uri.netloc != host or host.endswith('.') or host.endswith(('.local', '.localhost')) or host == 'metadata.google.internal':
        raise ValueError('Expected a canonical public HTTPS source.json URL')
    labels = host.split('.')
    if len(labels) < 2 or not re.fullmatch(r'[a-z][a-z0-9-]*', labels[-1]) or any(not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label) for label in labels) or any(part in ('.', '..') for part in uri.path.split('/')):
        raise ValueError('Invalid source hostname or path')
    return value


def image_info(data, png):
    if png:
        if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
            raise ValueError('Expected PNG preview')
        width, height = struct.unpack('>II', data[16:24])
        offset = 8
        while offset < len(data):
            size = int.from_bytes(data[offset:offset + 4], 'big')
            if data[offset + 4:offset + 8] == b'acTL':
                raise ValueError('Preview must be static')
            offset += 12 + size
        return width, height, 1, 0
    if data[:4] != b'RIFF' or data[8:12] != b'WEBP' or int.from_bytes(data[4:8], 'little') + 8 != len(data):
        raise ValueError('Expected WebP media')
    width = height = None
    frames = duration = 0
    offset = 12
    while offset + 8 <= len(data):
        tag = data[offset:offset + 4]
        size = int.from_bytes(data[offset + 4:offset + 8], 'little')
        chunk = data[offset + 8:offset + 8 + size]
        if len(chunk) != size:
            raise ValueError('Truncated WebP chunk')
        if tag == b'VP8X':
            width = 1 + int.from_bytes(chunk[4:7], 'little')
            height = 1 + int.from_bytes(chunk[7:10], 'little')
        elif tag == b'VP8 ' and width is None:
            if chunk[3:6] != b'\x9d\x01\x2a':
                raise ValueError('Invalid VP8 frame')
            width, height = (n & 0x3fff for n in struct.unpack('<HH', chunk[6:10]))
        elif tag == b'VP8L' and width is None:
            if not chunk or chunk[0] != 0x2f:
                raise ValueError('Invalid VP8L frame')
            bits = int.from_bytes(chunk[1:5], 'little')
            width, height = (bits & 0x3fff) + 1, ((bits >> 14) & 0x3fff) + 1
        elif tag == b'ANMF':
            frames += 1
            duration += int.from_bytes(chunk[12:15], 'little')
        offset += 8 + size + (size & 1)
    if width is None or height is None or offset != len(data):
        raise ValueError('Invalid WebP dimensions or chunks')
    return width, height, frames or 1, duration


def prepare_pack(directory, staging, published_at):
    path = directory / 'manifest.json'
    if path.is_symlink():
        raise ValueError('Symlinked manifests are not allowed')
    raw = path.read_bytes()
    if len(raw) > 256 * 1024 or raw.startswith(b'\xef\xbb\xbf'):
        raise ValueError('Invalid manifest size or BOM')
    manifest = json.loads(raw.decode('utf-8'), object_pairs_hook=unique_object, parse_constant=invalid_constant)
    validate_depth(manifest)
    if manifest.get('schema') != 'meshex.stickers.pack' or type(manifest.get('version')) is not int or manifest['version'] != 1:
        raise ValueError('Expected meshex.stickers.pack schema 1')
    pack_id = manifest['id']
    if not isinstance(pack_id, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,48}', pack_id):
        raise ValueError('Invalid pack ID')
    text(manifest['title'], 160)
    text(manifest['revision'], 64)
    if not isinstance(manifest['authors'], list) or len(manifest['authors']) > 16:
        raise ValueError('Invalid authors')
    for author in manifest['authors']:
        text(author['name'], 160)
    if manifest['license'] is not None:
        text(manifest['license']['id'], 160)
    for link in [manifest.get('attribution_url'), (manifest['license'] or {}).get('url')]:
        if link is not None:
            parsed = urlsplit(text(link, 2048))
            if parsed.scheme != 'https' or not parsed.hostname or parsed.username is not None:
                raise ValueError('Expected HTTPS metadata link')
    stickers = manifest['stickers']
    if not isinstance(stickers, list) or not 1 <= len(stickers) <= 100:
        raise ValueError('Invalid sticker count')
    files = {}
    ids = set()
    for sticker in stickers:
        sid = sticker['id']
        if not isinstance(sid, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,24}', sid) or sid in ids:
            raise ValueError('Invalid or duplicate sticker ID')
        ids.add(sid)
        text(sticker['alt'], 256)
        text(sticker.get('emoji', ''), 64, empty=True)
        if type(sticker['animated']) is not bool:
            raise ValueError('Invalid animation flag')
        animated = sticker['animated']
        if animated:
            number(sticker['frame_count'], 90)
            number(sticker['duration_ms'], 3000)
            if not sticker.get('preview'):
                raise ValueError('Animation requires PNG preview')
        for key in ('media', 'preview'):
            media = sticker.get(key)
            if media is None:
                if key == 'media':
                    raise ValueError('Missing media')
                continue
            digest = media['sha256']
            if not isinstance(digest, str) or not re.fullmatch(r'[a-f0-9]{64}', digest):
                raise ValueError('Invalid media hash')
            relative = f"media/{digest}.{'png' if key == 'preview' else 'webp'}"
            if media['url'] != relative:
                raise ValueError('Invalid media path')
            number(media['bytes'], 5 * 1024 * 1024)
            number(media['width'], 512)
            number(media['height'], 512)
            media_path = directory / relative
            if media_path.is_symlink() or (directory / 'media').is_symlink():
                raise ValueError('Symlinked media is not allowed')
            data = media_path.read_bytes()
            if len(data) != media['bytes'] or hashlib.sha256(data).hexdigest() != digest:
                raise ValueError('Media integrity failure')
            width, height, count, duration = image_info(data, key == 'preview')
            if (width, height) != (media['width'], media['height']):
                raise ValueError('Media dimensions mismatch')
            expected_count = sticker['frame_count'] if animated and key == 'media' else 1
            if count != expected_count or (animated and key == 'media' and duration != sticker['duration_ms']):
                raise ValueError('Animation metadata mismatch')
            files[relative] = data
    size = sum(len(data) for data in files.values())
    if size > 50 * 1024 * 1024:
        raise ValueError('Pack too large')
    digest = hashlib.sha256(raw).hexdigest()
    dest = staging / 'packs' / digest
    dest.mkdir(parents=True, exist_ok=True)
    (dest / 'manifest.json').write_bytes(raw)
    for name, data in files.items():
        target = dest / name
        target.parent.mkdir(exist_ok=True)
        target.write_bytes(data)
    return {'id': pack_id, 'revision': manifest['revision'], 'title': manifest['title'],
            'pack_sha256': digest, 'manifest_url': f'packs/{digest}/manifest.json',
            'sticker_count': len(stickers), 'download_bytes': size,
            'published_at': published_at, 'status': 'active'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pack-dir', action='append', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--source-url', type=source_url, required=True)
    parser.add_argument('--name', required=True)
    parser.add_argument('--operator-name', required=True)
    parser.add_argument('--operator-contact', required=True)
    parser.add_argument('--published-at', required=True, help='UTC timestamp ending in Z')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Output must not exist; immutable revisions must never be overwritten')
    if any(args.output.resolve().is_relative_to(p.resolve()) for p in args.pack_dir):
        parser.error('Output must be outside the input pack directories')
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z', args.published_at):
        parser.error('published-at must be UTC')
    datetime.fromisoformat(args.published_at)
    descriptor = {'schema': 'meshex.stickers.source', 'version': 1,
                  'canonical_url': args.source_url, 'catalog_url': 'catalog.json',
                  'name': text(args.name, 160),
                  'operator': {'name': text(args.operator_name, 160), 'contact': text(args.operator_contact, 256)}}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix='.sticker-publish-', dir=args.output.parent))
    try:
        revisions = {}
        for directory in args.pack_dir:
            revision = prepare_pack(directory, staging, args.published_at)
            revisions[revision['pack_sha256']] = revision
        if len(revisions) > 200:
            raise ValueError('Too many pack revisions')
        catalog = {'schema': 'meshex.stickers.catalog', 'version': 1, 'packs': list(revisions.values())}
        for name, obj, limit in [('source.json', descriptor, 64 * 1024), ('catalog.json', catalog, 1024 * 1024)]:
            data = (json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n').encode('utf-8')
            if len(data) > limit:
                raise ValueError('Source metadata too large')
            (staging / name).write_bytes(data)
        staging.rename(args.output)
    finally:
        if staging.exists():
            shutil.rmtree(staging)
    print(f'Prepared {len(revisions)} revision(s) in {args.output}. Nothing was uploaded.')


if __name__ == '__main__':
    main()
