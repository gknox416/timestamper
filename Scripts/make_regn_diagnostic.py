"""Create a diagnostic copy of ONLY the canonical fixture, not a general writer.

The regn timestamp interpretation is experimental pending a Pro Tools import check.
Run from any directory: python3 Scripts/make_regn_diagnostic.py
"""
from pathlib import Path
import hashlib
import struct

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'TestFixtures/ProTools/PT_23.976_48k_24bit_01h.wav'
DESTINATION = ROOT / 'Outputs/RegnDiagnostic/PT_23.976_48k_24bit_ZERO_BEXT_REGN_TEST_01.wav'
EXPECTED_SHA256 = 'b09af898360733a47cd61b86957f238da86408f387c92dafef1e7aafe957014e'


def main():
    original = SOURCE.read_bytes()
    if hashlib.sha256(original).hexdigest() != EXPECTED_SHA256:
        raise ValueError('This experiment only supports the exact canonical fixture.')

    # Absolute offsets verified in this hash-locked fixture:
    # BEXT payload +338; regn payload +44 and +52.
    fields = (430, 22442, 22450)
    output = bytearray(original)
    for offset in fields:
        if struct.unpack_from('<Q', original, offset)[0] != 172972800:
            raise ValueError('Unexpected timestamp field.')
        struct.pack_into('<Q', output, offset, 0)

    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    with DESTINATION.open('xb') as file:
        file.write(output)
    result = DESTINATION.read_bytes()
    allowed = {offset + byte for offset in fields for byte in range(8)}
    if len(result) != len(original):
        raise ValueError('Output size verification failed.')
    if any(a != b and i not in allowed for i, (a, b) in enumerate(zip(original, result))):
        raise ValueError('Unrelated bytes changed.')
    if any(struct.unpack_from('<Q', result, offset)[0] != 0 for offset in fields):
        raise ValueError('Timestamp verification failed.')
    if result[16384:22390] != original[16384:22390]:
        raise ValueError('Audio changed.')
    if SOURCE.read_bytes() != original:
        raise ValueError('Source changed.')
    print(f'Diagnostic copy: {DESTINATION}')
    print('BEXT and both candidate regn timestamp fields are zero.')
    print('All other bytes, file size, audio and source are unchanged.')
    print('Pro Tools behavior is NOT yet verified.')


if __name__ == '__main__':
    main()
