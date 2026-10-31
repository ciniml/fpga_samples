# SPDX-License-Identifier: BSL-1.0
# Copyright Kenta Ida 2026.
"""Minimal KiCad s-expression reader/writer used by the generator scripts."""
import re


class Sym(str):
    """Unquoted atom."""


_TOK = re.compile(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()"]+')


def parse(s):
    st = [[]]
    for t in _TOK.findall(s):
        if t == '(':
            st.append([])
        elif t == ')':
            x = st.pop()
            st[-1].append(x)
        elif t.startswith('"'):
            st[-1].append(re.sub(r'\\(.)', lambda m: '\n' if m.group(1) == 'n' else m.group(1), t[1:-1]))
        else:
            st[-1].append(Sym(t))
    return st[0]


def q(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'


def atom(x):
    if isinstance(x, Sym):
        return str(x)
    if isinstance(x, str):
        return q(x)
    if isinstance(x, bool):
        return 'yes' if x else 'no'
    if isinstance(x, float):
        r = ('%.4f' % x).rstrip('0').rstrip('.')
        return '0' if r in ('-0', '') else r
    return str(x)


def dump(x, ind=0):
    if not isinstance(x, list):
        return atom(x)
    i = 0
    head = []
    while i < len(x) and not isinstance(x[i], list):
        head.append(atom(x[i]))
        i += 1
    rest = x[i:]
    if not rest:
        return '(' + ' '.join(head) + ')'
    # short lists of only atoms-lists on one line (e.g. (at 1 2 0))
    s = '(' + ' '.join(head)
    for e in rest:
        s += '\n' + '\t' * (ind + 1) + dump(e, ind + 1)
    s += '\n' + '\t' * ind + ')'
    return s


def find(x, name):
    return [e for e in x if isinstance(e, list) and e and e[0] == name]


def find1(x, name):
    r = find(x, name)
    return r[0] if r else None


def load_lib(libfile):
    return parse(open(libfile).read())[0]


def get_symbol(lib, name):
    for e in find(lib, 'symbol'):
        if e[1] == name:
            return e
    raise KeyError(name)
