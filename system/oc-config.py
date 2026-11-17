#!/usr/bin/python3 -I
"""Adds, removes or shows the TSMetalEnabler.kext entry in an OpenCore config.plist (Kernel -> Add).

Usage: oc-config.py add|remove|show <config.plist>
"add" appends the entry after every other kext (so after Lilu and AMFIPass), Tahoe only
(MinKernel 25.0.0, MaxKernel 25.99.99), and does nothing if the entry is already there.
The file is rewritten only when something changes; every other key keeps its value, type and order.
"""
import plistlib
import sys

ENTRY = {
    'Arch': 'x86_64',
    'BundlePath': 'TSMetalEnabler.kext',
    'Comment': 'TeraScale Metal Shim',
    'Enabled': True,
    'ExecutablePath': 'Contents/MacOS/TSMetalEnabler',
    'MaxKernel': '25.99.99',
    'MinKernel': '25.0.0',
    'PlistPath': 'Contents/Info.plist',
}


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ('add', 'remove', 'show'):
        sys.exit('usage: oc-config.py add|remove|show <config.plist>')
    action, path = sys.argv[1], sys.argv[2]
    with open(path, 'rb') as f:
        config = plistlib.load(f)
    kexts = config['Kernel']['Add']
    found = [i for i, k in enumerate(kexts) if k.get('BundlePath') == ENTRY['BundlePath']]

    if action == 'show':
        print(f'TSMetalEnabler.kext: Kernel:Add:{found[0]} {kexts[found[0]]}' if found else 'TSMetalEnabler.kext: no entry')
        return
    if action == 'add':
        if found:
            print(f'TSMetalEnabler.kext: entry already present (Kernel:Add:{found[0]})')
            return
        if not any(k.get('BundlePath') == 'Lilu.kext' and k.get('Enabled') for k in kexts):
            sys.exit('Lilu.kext is not enabled in Kernel:Add, stopping')
        kexts.append(dict(ENTRY))
        message = f'TSMetalEnabler.kext: entry added as Kernel:Add:{len(kexts) - 1}'
    else:
        if not found:
            print('TSMetalEnabler.kext: no entry to remove')
            return
        for i in reversed(found):
            del kexts[i]
        message = f'TSMetalEnabler.kext: entry Kernel:Add:{found[0]} removed'
    with open(path, 'wb') as f:
        plistlib.dump(config, f, fmt=plistlib.FMT_XML, sort_keys=False)
    print(message)


if __name__ == '__main__':
    main()
