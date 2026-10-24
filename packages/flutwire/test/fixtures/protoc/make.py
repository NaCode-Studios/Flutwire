"""Writes the fixtures next to it with protoc and its Python runtime:
the descriptor set, and messages serialised by the code protoc generates.

    python3 -m venv venv && venv/bin/pip install grpcio-tools
    venv/bin/python make.py
"""
import importlib
import importlib.resources
import os
import sys
import tempfile

from google.protobuf import descriptor_pb2, duration_pb2, timestamp_pb2
from grpc_tools import protoc

here = os.path.dirname(os.path.abspath(__file__))
well_known = str(importlib.resources.files('grpc_tools') / '_proto')

with tempfile.TemporaryDirectory() as generated:
    status = protoc.main([
        'protoc', f'-I{here}', f'-I{well_known}', f'--python_out={generated}',
        f'--descriptor_set_out={here}/check.desc', '--include_imports',
        f'{here}/check.proto', f'{here}/legacy.proto',
    ])
    if status != 0:
        sys.exit(status)
    sys.path.insert(0, generated)
    check = importlib.import_module('check_pb2')
    legacy = importlib.import_module('legacy_pb2')


def write(name, message, extra=b''):
    with open(f'{here}/{name}.bin', 'wb') as out:
        # Sorted map entries, so that a run of this script writes the same bytes.
        out.write(message.SerializeToString(deterministic=True) + extra)


write('scalars', check.Scalars(
    d=3.141592653589793, f=0.1, i32=-2147483648, i64=-9223372036854775808,
    u32=4294967295, u64=18446744073709551615, s32=-1, s64=-9007199254740993,
    fx32=4294967295, fx64=18446744073709551615, sf32=-5, sf64=-6, b=True,
    s='héllo ☃ \U0001F600', raw=b'\x01\x02\xff',
))

club = check.Club(
    name='Hikers',
    level=check.LEVEL_HIGH,
    tags=['outdoor', 'weekend'],
    scores=[3, 5, 8, -1],
    ratios=[0.5, 1.25],
    counts={'x': 1, 'y': 2},
    members={
        1: check.Club.Member(handle='ada', admin=True),
        2: check.Club.Member(handle='bob'),
    },
    address=check.Address(city='London', street="St James's Square"),
    branches=[check.Address(city='Bath'), check.Address(city='Leeds')],
    email='club@example.com',
    rank=0,
    founded=timestamp_pb2.Timestamp(seconds=1700000000, nanos=500000000),
    season=duration_pb2.Duration(seconds=7776000, nanos=1500000),
    levels=[check.LEVEL_LOW, check.LEVEL_NEGATIVE, check.LEVEL_HIGH],
    kind=check.Club.KIND_TEAM,
    scalars=check.Scalars(i32=7, s='nested'),
)
write('club', club)

by_phone = check.Club(name='Phone', phone=442079460000)
write('club_phone', by_phone)

by_office = check.Club(name='Office', office=check.Address(city='Leeds'))
write('club_office', by_office)

# A field the schema does not know, as an older client reading a newer server
# would meet one: number 99, a varint of 5.
write('club_unknown', check.Club(name='Hikers'), extra=b'\x98\x06\x05')

write('get_request', check.GetClubRequest(name='Hikers'))

write('old', legacy.Old(name='Ada', loose=[1, 2, 3], tight=[4, 5, 6],
                        blob=b'\x00\x01'))
