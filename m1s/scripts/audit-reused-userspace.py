#!/usr/bin/env python3
"""Assert that a packaged filesystem preserves official userspace and metadata."""
import hashlib
import json
import os
import stat
import sys
from collections import defaultdict
from pathlib import Path

MODULES = 'usr/lib/modules/'
EXCEPTIONS = {'etc/rauc/keyring.pem', 'usr/lib/os-release'}


def inventory(root):
    entries, links = {}, defaultdict(list)
    for base, dirs, files in os.walk(root):
        for name in dirs + files:
            path = Path(base) / name
            info = path.lstat()
            relative = str(path.relative_to(root))
            entry = {
                'mode': info.st_mode, 'uid': info.st_uid, 'gid': info.st_gid,
                'xattrs': {key: os.getxattr(path, key, follow_symlinks=False).hex()
                           for key in os.listxattr(path, follow_symlinks=False)},
            }
            if stat.S_ISREG(info.st_mode):
                with path.open('rb') as stream:
                    entry['sha256'] = hashlib.file_digest(stream, 'sha256').hexdigest()
                entry['mtime_ns'] = info.st_mtime_ns
                links[info.st_ino].append(relative)
            elif path.is_symlink():
                entry['target'] = os.readlink(path)
                entry['mtime_ns'] = info.st_mtime_ns
            elif not path.is_dir():
                entry['rdev'] = info.st_rdev
            entries[relative] = entry
    groups = sorted(sorted(paths) for paths in links.values() if len(paths) > 1
                    and all(not p.startswith(MODULES) for p in paths))
    return entries, groups


def main():
    official, result, custom_modules, output = map(Path, sys.argv[1:])
    before, before_links = inventory(official)
    after, after_links = inventory(result)
    added = sorted(after.keys() - before.keys())
    removed = sorted(before.keys() - after.keys())
    changed = sorted(p for p in before.keys() & after.keys() if before[p] != after[p])
    allowed = lambda p: p.startswith(MODULES) or p in EXCEPTIONS
    assert not removed, removed
    assert all(p.startswith(MODULES) for p in added), added
    assert all(allowed(p) for p in changed), [p for p in changed if not allowed(p)]
    assert before_links == after_links, 'Official userspace hardlink groups changed'
    expected_modules, _ = inventory(custom_modules)
    actual_modules, _ = inventory(result / 'usr/lib/modules')
    assert expected_modules == actual_modules, 'Packaged modules differ from matching kernel build'
    assert (result / 'usr/lib/firmware/rtw89/rtw8851b_fw.bin').is_file()
    unchanged = sum(not allowed(p) for p in before)
    report = {
        'official_paths': len(before), 'packaged_paths': len(after),
        'unchanged_paths_outside_modules_and_two_metadata_files': unchanged,
        'added': added, 'removed': removed,
        'changed_outside_module_tree': [p for p in changed if not p.startswith(MODULES)],
        'changed_paths_within_module_tree': sum(p.startswith(MODULES) for p in changed),
        'matching_kernel_modules_verified': True,
        'userspace_hardlink_groups_preserved': len(before_links),
        'comparison': 'File bytes, file/symlink mtimes, ownership, modes, xattrs, symlink targets, device numbers and userspace hardlinks; directory mtimes/inode numbers excluded.',
        'boot_and_spl_payloads': 'omitted',
    }
    output.write_text(json.dumps(report, indent=2) + '\n')
    print(f'Preserved {unchanged} official filesystem paths outside modules and two metadata files.')


if __name__ == '__main__':
    main()
