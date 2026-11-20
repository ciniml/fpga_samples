# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Minimal S-expression reader / writer for KiCad files.

Atoms are kept as Python str (quoted strings keep their quotes so they are
written back unchanged); lists are Python lists.
"""
import re

_TOK = re.compile(r'\s*(\(|\)|"(?:[^"\\]|\\.)*"|[^\s()"]+)')


def parse(text):
    stack = [[]]
    pos = 0
    n = len(text)
    while pos < n:
        m = _TOK.match(text, pos)
        if not m:
            if text[pos:].strip() == '':
                break
            raise ValueError(f'bad token at {pos}: {text[pos:pos + 20]!r}')
        tok = m.group(1)
        pos = m.end()
        if tok == '(':
            stack.append([])
        elif tok == ')':
            lst = stack.pop()
            stack[-1].append(lst)
        else:
            stack[-1].append(tok)
    return stack[0]


def dump(x, indent=0):
    if not isinstance(x, list):
        return x
    # short lists on one line
    flat = '(' + ' '.join(dump(e) if not isinstance(e, list) else dump(e, 0) for e in x) + ')'
    if len(flat) < 100 and '\n' not in flat:
        return flat
    pad = '\t' * (indent + 1)
    out = '(' + (x[0] if x and not isinstance(x[0], list) else '')
    rest = x[1:] if x and not isinstance(x[0], list) else x
    for e in rest:
        if isinstance(e, list):
            out += '\n' + pad + dump(e, indent + 1)
        else:
            out += ' ' + e
    out += '\n' + '\t' * indent + ')'
    return out


def q(s):
    """quote a Python string as a KiCad string atom"""
    return '"' + str(s).replace('\\', '\\\\').replace('"', '\\"') + '"'


def find(lst, head):
    """first sub-list whose head is `head`"""
    for e in lst:
        if isinstance(e, list) and e and e[0] == head:
            return e
    return None


def find_all(lst, head):
    return [e for e in lst if isinstance(e, list) and e and e[0] == head]


def lib_symbol(lib_path, name):
    """the (symbol "name" ...) list from a .kicad_sym file"""
    top = parse(open(lib_path).read())[0]
    for e in find_all(top, 'symbol'):
        if e[1] == q(name):
            return e
    raise KeyError(name)
