"""Run real synthetic-file organizer tests without an Android device or SDK.

Supply an existing trusted Kotlin compiler distribution and JUnit 4/Hamcrest
JARs. This script does not download dependencies or touch user media.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kotlinc', required=True, type=Path)
    parser.add_argument('--junit', required=True, type=Path)
    parser.add_argument('--hamcrest', required=True, type=Path)
    args = parser.parse_args()
    compiler, junit, hamcrest = [p.resolve(strict=True) for p in
                               (args.kotlinc, args.junit, args.hamcrest)]
    root = Path(__file__).resolve().parents[2]
    package = 'com/aeidolon/vaultexplorer/organizer'
    main_source = root / 'android/app/src/main/kotlin' / package
    test_source = root / 'android/app/src/test/kotlin' / package
    sources = [main_source / 'OrganizerTransfer.kt', main_source / 'RawOrganizerFiles.kt',
               test_source / 'OrganizerTransferTest.kt', test_source / 'OrganizerCrashBoundaryTest.kt']
    with tempfile.TemporaryDirectory(prefix='organizer-test-build-') as directory:
        jar = Path(directory) / 'tests.jar'
        subprocess.run(['bash', str(compiler), *map(str, sources), '-cp', str(junit),
                        '-include-runtime', '-d', str(jar)], check=True)
        subprocess.run(['java', '-cp', ':'.join(map(str, (jar, junit, hamcrest))),
                        'org.junit.runner.JUnitCore',
                        'com.aeidolon.vaultexplorer.organizer.OrganizerTransferTest',
                        'com.aeidolon.vaultexplorer.organizer.OrganizerCrashBoundaryTest'], check=True)


if __name__ == '__main__':
    main()
