#!/usr/bin/env python3
"""APR1 (Apache MD5) password hashing -- fallback for generate-htpasswd.sh.

Exists because neither `htpasswd` (httpd-tools) nor `openssl` is guaranteed to
be installed on a Falcon host -- on the trader desk neither is -- while Python 3
always is. Without a working generator the operator cannot create
`users.htpasswd`, and Traefik refuses to load a basicAuth middleware whose
usersFile is missing, which takes the dashboard down rather than merely leaving
it unauthenticated (falcon-gateway#1).

Prefer bcrypt when available. This is the last resort:

    htpasswd -nbB   (bcrypt, best)
    openssl passwd -apr1
    this module

APR1 is MD5-based and weak by modern standards. It is acceptable here only
because it guards a LAN admin surface that sits in front of falcon-trader's own
token authentication -- it is defence in depth, not the only lock.

Algorithm: the original Apache/FreeBSD md5crypt, as described in
`crypt-md5.c`. Deterministic for a given (password, salt).

Usage:
    python3 apr1.py USERNAME PASSWORD      -> "user:$apr1$salt$hash"
    python3 apr1.py --selftest
"""

from __future__ import annotations

import hashlib
import secrets
import sys

MAGIC = b"$apr1$"
ITOA64 = b"./0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
SALT_CHARS = ITOA64[2:]  # conventional: alphanumeric salts


def _to64(value: int, length: int) -> bytes:
    out = bytearray()
    for _ in range(length):
        out.append(ITOA64[value & 0x3F])
        value >>= 6
    return bytes(out)


def apr1(password: str, salt: str | None = None) -> str:
    """Return the APR1 hash string ``$apr1$<salt>$<checksum>``."""
    if salt is None:
        salt = "".join(
            chr(SALT_CHARS[secrets.randbelow(len(SALT_CHARS))]) for _ in range(8)
        )
    salt = salt[:8]

    pw = password.encode("utf-8")
    sb = salt.encode("ascii")

    # Primary context.
    ctx = hashlib.md5(pw + MAGIC + sb)

    # Alternate digest of password + salt + password.
    alternate = hashlib.md5(pw + sb + pw).digest()

    # Append the alternate digest, one password-length worth.
    i = len(pw)
    while i > 0:
        ctx.update(alternate[: min(i, 16)])
        i -= 16

    # Then, for each bit of the password length: a NUL for a 1 bit, the first
    # password byte for a 0 bit. (Yes, this is as odd as it looks; it is what
    # the reference implementation does, and compatibility requires it.)
    i = len(pw)
    while i:
        ctx.update(b"\0" if i & 1 else pw[:1])
        i >>= 1

    final = ctx.digest()

    # 1000 rounds of deliberate slowness.
    for i in range(1000):
        c = hashlib.md5()
        c.update(pw if i & 1 else final)
        if i % 3:
            c.update(sb)
        if i % 7:
            c.update(pw)
        c.update(final if i & 1 else pw)
        final = c.digest()

    # Custom base64 with the reference implementation's byte ordering.
    out = bytearray()
    for a, b, c in ((0, 6, 12), (1, 7, 13), (2, 8, 14), (3, 9, 15), (4, 10, 5)):
        out += _to64((final[a] << 16) | (final[b] << 8) | final[c], 4)
    out += _to64(final[11], 2)

    return f"$apr1${salt}${out.decode('ascii')}"


def htpasswd_line(username: str, password: str, salt: str | None = None) -> str:
    if ":" in username:
        raise ValueError("username must not contain ':'")
    return f"{username}:{apr1(password, salt)}"


def _selftest() -> int:
    """Structural and determinism checks.

    Includes the published reference vector for
    (password="password", salt="12345678"). Note that no reference
    implementation was available on the machine where this was written --
    neither openssl nor htpasswd is installed there -- so the vector is pinned
    from published sources rather than generated locally. On a host that has
    one, confirming is one command:

        openssl passwd -apr1 -salt 12345678 password
    """
    ok = True

    h = apr1("password", "12345678")
    print(f"apr1('password', salt='12345678') = {h}")

    # The widely-published reference vector for this salt/password pair, as
    # produced by `openssl passwd -apr1 -salt 12345678 password`. Pinned so a
    # future edit that breaks compatibility fails loudly here rather than
    # silently locking everyone out of the gateway.
    EXPECTED = "$apr1$12345678$9pHAGSBYtlmFtid2xxNog0"
    if h != EXPECTED:
        print(f"FAIL: does not match the reference vector\n"
              f"  expected {EXPECTED}\n  got      {h}")
        ok = False

    if not h.startswith("$apr1$12345678$"):
        print("FAIL: prefix/salt not preserved"); ok = False
    if len(h.split("$")[-1]) != 22:
        print(f"FAIL: checksum length {len(h.split('$')[-1])}, expected 22"); ok = False
    if apr1("password", "12345678") != h:
        print("FAIL: not deterministic"); ok = False
    if apr1("password ", "12345678") == h:
        print("FAIL: different passwords collide"); ok = False
    if apr1("password", "87654321") == h:
        print("FAIL: different salts collide"); ok = False

    a, b = apr1("x"), apr1("x")
    if a == b:
        print("FAIL: random salts are not random"); ok = False
    if len(apr1("")) != len(h):
        print("FAIL: empty password changes output length"); ok = False

    alphabet = set(ITOA64.decode())
    if not set(h.split("$")[-1]) <= alphabet:
        print("FAIL: checksum uses characters outside the itoa64 alphabet"); ok = False

    line = htpasswd_line("falcon", "s3cret")
    if line.count(":") != 1 or not line.startswith("falcon:$apr1$"):
        print("FAIL: htpasswd line malformed"); ok = False

    print("SELFTEST PASS" if ok else "SELFTEST FAIL")
    return 0 if ok else 1


def main(argv) -> int:
    if len(argv) == 2 and argv[1] == "--selftest":
        return _selftest()
    if len(argv) == 2 and argv[1] == "--vector":
        print(apr1("password", "12345678"))
        return 0
    if len(argv) != 3:
        print(__doc__.strip().splitlines()[-3].strip(), file=sys.stderr)
        print("usage: apr1.py USERNAME PASSWORD | --selftest | --vector",
              file=sys.stderr)
        return 2
    print(htpasswd_line(argv[1], argv[2]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
