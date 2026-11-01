#!/usr/bin/env python3
"""Upload verified release files; switch release.json only after all uploads succeed."""
from __future__ import annotations

import ftplib
import hashlib
import json
import os
import re
import ssl
from pathlib import Path


def publish() -> None:
    config = {key: os.environ.get(key, '').strip() for key in
              ('FTP_HOST', 'FTP_USER', 'FTP_ROOT', 'FTP_PORT', 'FTP_TLS')}
    password = os.environ.get('FTP_PASSWORD', '')
    if not all((config['FTP_HOST'], config['FTP_USER'], config['FTP_ROOT'], password)):
        raise ValueError('Configure FTP_HOST, FTP_USER, FTP_PASSWORD and FTP_ROOT')
    tls = config['FTP_TLS'].lower() or 'true'
    if tls not in ('true', 'false'):
        raise ValueError('FTP_TLS must be true (explicit FTPS) or false (FTP)')
    root = Path(os.environ['RELEASES_ROOT'])
    manifest = (root / 'release.json').read_bytes()
    release = json.loads(manifest)
    version = release['version']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('Invalid version')
    files = release['files']
    if not files:
        raise ValueError('Empty release')
    # Validate every local file before changing anything on the server.
    for artifact in files.values():
        name = artifact['name']
        if not re.fullmatch(r'meshex-[a-z-]+\.(apk|ipa|zip|tar\.gz)', name):
            raise ValueError('Invalid artifact name')
        path = root / version / name
        with path.open('rb') as source:
            digest = hashlib.file_digest(source, 'sha256').hexdigest()
        if path.stat().st_size != artifact['size'] or digest != artifact['sha256']:
            raise ValueError(f'Local verification failed: {name}')
    ftp = ftplib.FTP_TLS(context=ssl.create_default_context()) if tls == 'true' else ftplib.FTP()
    try:
        ftp.connect(config['FTP_HOST'], int(config['FTP_PORT'] or '21'), timeout=120)
        ftp.login(config['FTP_USER'], password)
        if tls == 'true':
            ftp.prot_p()
        ftp.set_pasv(True)
        # FTP_ROOT must already exist, so a typo cannot create an unrelated tree.
        ftp.cwd(config['FTP_ROOT'])
        if version not in ftp.nlst():
            ftp.mkd(version)
        for artifact in files.values():
            name = artifact['name']
            remote = f'{version}/{name}'
            with (root / version / name).open('rb') as source:
                ftp.storbinary(f'STOR {remote}.uploading', source)
            ftp.voidcmd('TYPE I')
            if ftp.size(f'{remote}.uploading') != artifact['size']:
                raise RuntimeError(f'Remote size mismatch: {name}')
            ftp.rename(f'{remote}.uploading', remote)
            print(f'Uploaded {remote}', flush=True)
        # Keep the previous manifest if any upload failed. No old releases are deleted.
        from io import BytesIO
        ftp.storbinary('STOR release.json.uploading', BytesIO(manifest))
        ftp.rename('release.json.uploading', 'release.json')
        print(f'Published {version}', flush=True)
    finally:
        ftp.close()


if __name__ == '__main__':
    publish()
