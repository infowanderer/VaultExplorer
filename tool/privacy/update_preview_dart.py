"""Prepare an unsigned Dart-only preview update from the verified native base.

This is not a full Android/native rebuild. Run zipalign, sign with the existing
private preview key, and run check_preview_apk.py afterwards. Never distribute
this script's unsigned output directly.
"""
import argparse
import copy
import hashlib
from pathlib import Path
import struct
import subprocess
import zipfile

BASE_COMMIT = '2c664cb189296dc62d56c71b7cd760839363371a'
BASE_SHA256 = '87cb150291016f22045554dba6cb8b8b76a2acb037d75d52957d18bcefe5c1ad'


def runtime_segments(data):
    """Compare loader-visible engine bytes, allowing stripped debug sections."""
    if data[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', data, 18)[0] != 183:
        raise ValueError('Expected little-endian ARM64 ELF')
    offset = struct.unpack_from('<Q', data, 32)[0]
    size, count = struct.unpack_from('<HH', data, 54)
    result = []
    for index in range(count):
        kind, flags, start, address, _, length, memory, alignment = struct.unpack_from(
            '<IIQQQQQQ', data, offset + index * size)
        if kind != 1:
            continue
        segment = bytearray(data[start:start + length])
        if start == 0:
            # e_shoff/e_shentsize/e_shnum/e_shstrndx change when debug sections
            # are stripped. No runtime address, size or program-header is masked.
            segment[40:48] = bytes(8)
            segment[58:64] = bytes(6)
        result.append((flags, address, memory, alignment, hashlib.sha256(segment).hexdigest()))
    if not result:
        raise ValueError('No runtime load segments')
    return result


def update(base, flutter_output, engine_jar, output):
    base, flutter_output, output = Path(base), Path(flutter_output), Path(output)
    if output.resolve() == base.resolve():
        raise ValueError('Output must not overwrite the signed base')
    if hashlib.sha256(base.read_bytes()).hexdigest() != BASE_SHA256:
        raise ValueError('Base APK is not the previously verified preview')
    repo = Path(__file__).resolve().parents[2]
    subprocess.run(['git', 'diff', '--exit-code', BASE_COMMIT, '--',
                    'android', 'native', 'packages', 'pubspec.yaml', 'pubspec.lock',
                    '.flutter', 'CMakeLists.txt'], cwd=repo, check=True,
                   stdout=subprocess.DEVNULL)
    app = (flutter_output / 'arm64-v8a/app.so').read_bytes()
    runtime_segments(app)
    assets = {p.relative_to(flutter_output).as_posix(): p.read_bytes()
              for p in (flutter_output / 'flutter_assets').rglob('*') if p.is_file()}
    if not assets or 'flutter_assets/kernel_blob.bin' in assets:
        raise ValueError('A release Flutter asset bundle is required')
    replacements = {'lib/arm64-v8a/libapp.so': app,
                    **{'assets/' + name: data for name, data in assets.items()}}
    retained = {}
    with zipfile.ZipFile(base) as original, zipfile.ZipFile(engine_jar) as engine:
        engine_name = next(n for n in engine.namelist() if n.endswith('/libflutter.so'))
        if runtime_segments(original.read('lib/arm64-v8a/libflutter.so')) != runtime_segments(engine.read(engine_name)):
            raise ValueError('Pinned SDK engine does not match the base runtime')
        with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as target:
            names = set(original.namelist())
            for info in original.infolist():
                name = info.filename
                signature = name.upper().startswith('META-INF/') and (
                    name.upper().endswith(('.SF', '.RSA', '.DSA', '.EC')) or
                    name.upper() == 'META-INF/MANIFEST.MF')
                if signature or name == 'lib/arm64-v8a/libapp.so' or name.startswith('assets/flutter_assets/'):
                    continue
                data = original.read(name)
                retained[name] = hashlib.sha256(data).digest()
                target.writestr(copy.copy(info), data)
            for name, data in replacements.items():
                info = copy.copy(original.getinfo(name)) if name in names else zipfile.ZipInfo(name)
                if name not in names:
                    info.compress_type = zipfile.ZIP_STORED if name.endswith('.so') else zipfile.ZIP_DEFLATED
                target.writestr(info, data)
    with zipfile.ZipFile(output) as result:
        if len(result.namelist()) != len(set(result.namelist())):
            raise ValueError('Duplicate ZIP members')
        for name, digest in retained.items():
            if hashlib.sha256(result.read(name)).digest() != digest:
                raise ValueError('Retained native/Android file changed: ' + name)
        for name, data in replacements.items():
            if result.read(name) != data:
                raise ValueError('Updated Flutter artifact differs: ' + name)
    print(f'Prepared unsigned update: {len(retained)} unchanged entries; '
          f'{len(replacements)} rebuilt Flutter entries')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base')
    parser.add_argument('flutter_output')
    parser.add_argument('engine_jar')
    parser.add_argument('output')
    args = parser.parse_args()
    update(args.base, args.flutter_output, args.engine_jar, args.output)
