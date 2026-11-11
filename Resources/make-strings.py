#!/usr/bin/env python3
"""Writes Resources/en.lproj/Localizable.strings from the dictionary in Resources/translations-en.py."""
import os
here = os.path.dirname(os.path.abspath(__file__))
ns = {}
exec(open(os.path.join(here, 'translations-en.py'), encoding='utf-8').read(), ns)
def esc(s): return s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
out = '/* English UI. Keys are the Czech source strings. */\n\n' + ''.join(
    '"%s" = "%s";\n' % (esc(k), esc(v)) for k, v in sorted(ns['T'].items()))
path = os.path.join(here, 'en.lproj', 'Localizable.strings')
if not os.path.exists(path) or open(path, encoding='utf-8').read() != out:
    open(path, 'w', encoding='utf-8').write(out)
