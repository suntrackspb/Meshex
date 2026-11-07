#!/usr/bin/env python3
"""Prepare an optional static-server catalog from local, already prepared packs.

Input: <media>/<pack>/source.json, <id>.webp, and <id>.png for animations.
Output is local only; this tool never uploads or publishes any files.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--media', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--pack', action='append', required=True,
                        help='Prepared pack directory name; repeat to select packs explicitly')
    args = parser.parse_args()
    if args.output.resolve() == args.media.resolve():
        parser.error('Output must differ from input')
    args.output.mkdir(parents=True, exist_ok=True)
    packs = []
    for name in args.pack:
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,48}', name):
            parser.error('Invalid pack name')
        source = args.media / name
        info = json.loads((source / 'source.json').read_text())
        destination = args.output / name
        destination.mkdir(exist_ok=True)

        def media(sticker_id, extension):
            path = source / f'{sticker_id}.{extension}'
            data = path.read_bytes()
            if not 0 < len(data) <= 5 * 1024 * 1024:
                raise ValueError(f'Invalid file size: {path}')
            shutil.copyfile(path, destination / path.name)
            return {'url': f'{name}/{path.name}', 'bytes': len(data),
                    'sha256': hashlib.sha256(data).hexdigest()}

        stickers = []
        for item in info['stickers']:
            sticker_id = item['id']
            if not re.fullmatch(r'[A-Za-z0-9_-]{1,24}', sticker_id):
                raise ValueError('Invalid sticker ID')
            animated = item.get('animated', False)
            sticker = {'id': sticker_id, 'emoji': item.get('emoji', ''),
                       'animated': animated, 'media': media(sticker_id, 'webp')}
            if animated:
                sticker['preview'] = media(sticker_id, 'png')
            stickers.append(sticker)
        packs.append({'id': name, 'title': info['title'],
                      'author': info.get('author'), 'source': info.get('source'),
                      'license': info.get('license'), 'stickers': stickers})
    (args.output / 'catalog.json').write_text(
        json.dumps({'version': 1, 'packs': packs}, ensure_ascii=False, indent=2) + '\n')
    print(f'Prepared {len(packs)} pack(s) in {args.output}. Nothing was uploaded.')


if __name__ == '__main__':
    main()
