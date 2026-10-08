#!/usr/bin/env bash
# Exercise the shipped selector in a disposable Git repo with stubbed child duties.
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$HERE/lib/fixture-env.sh"
python3 - "$HERE/../../.." "${CHECK_PUSH_SOURCE:-}" <<'PY'
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]).resolve()
selector = Path(sys.argv[2]) if sys.argv[2] else source / '.github/scripts/check-push.sh'
components = ('linear', 'estate-hooks', 'plugin', 'shared-copy', 'standalone')
with tempfile.TemporaryDirectory(prefix='core-check-push-') as temporary:
    root = Path(temporary)
    env = dict(os.environ)

    def write(name, text):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def run(args, expected=0, extra=None):
        result = subprocess.run(args, cwd=root, env=dict(env, **(extra or {})), text=True, capture_output=True)
        output = result.stdout + result.stderr
        assert result.returncode == expected, (args, result.returncode, output)
        return output

    def commit():
        run(['git', 'add', '.'])
        run(['git', 'commit', '-qm', 'fixture'])
        return run(['git', 'rev-parse', 'HEAD']).strip()

    def scope(base, head):
        return dict(PRE_COMMIT_FROM_REF=base, PRE_COMMIT_TO_REF=head)

    def check(component, extra, selected=True):
        output = run(['bash', '.github/scripts/check-push.sh', component], extra=extra)
        if selected:
            assert 'CALLED:' + component in output, output
        else:
            assert 'no affected inputs' in output and 'CALLED:' not in output, output

    run(['git', 'init', '-q'])
    run(['git', 'config', 'user.name', 'Fixture'])
    run(['git', 'config', 'user.email', 'fixture@example.invalid'])
    write('.github/scripts/check-push.sh', selector.read_text())
    write('plugins/estate-hooks/tests/lib/fixture-env.sh', (source / 'plugins/estate-hooks/tests/lib/fixture-env.sh').read_text())
    write('plugins/estate-hooks/tests/probe.test.sh', 'echo CALLED:estate-hooks\nexit "${FIXTURE_EXIT:-0}"\n')
    write('.github/scripts/standalone-check.sh', 'echo CALLED:standalone\n')
    write('.github/scripts/drift-check.sh', 'echo CALLED:shared-copy\n')
    write('.pre-commit-hooks.yaml', '[]\n')
    write('plugins/core/skills/linear/scripts/input.py', '# fixture\n')
    for tool, component in [('uvx', 'linear'), ('claude', 'plugin')]:
        path = write('tools/' + tool, '#!/bin/sh\necho CALLED:' + component + '\n')
        path.chmod(0o755)
    write('.gitignore', 'tool-cache/\n')
    write('README.md', 'fixture\n')
    env.update(PATH=str(root / 'tools') + ':' + env['PATH'], DOTTY_CHECKOUT=str(root))
    base = commit()
    # One direct dependency for each row; each must select its component.
    cases = [('linear', 'pyproject.toml'), ('estate-hooks', 'plugins/estate-hooks/hooks/input.sh'),
             ('plugin', '.claude-plugin/marketplace.json'), ('shared-copy', '.github/scripts/drift-check.sh'),
             ('standalone', '.github/scripts/standalone-check.sh')]
    for component, path in cases:
        existing = (root / path).read_text() if (root / path).exists() else ''
        write(path, existing + '# changed fixture\n')
        head = commit()
        check(component, scope(base, head))
        base = head
    print('PASS: every component dependency dispatches its child duty')
    write('README.md', 'unrelated prose\n')
    head = commit()
    for component in components:
        check(component, scope(base, head), selected=False)
    base = head
    # Configuration is shared by all five components.
    write('.pre-commit-config.yaml', 'repos: []\n')
    head = commit()
    for component in components:
        check(component, scope(base, head))
    base = head
    run(['git', 'rm', 'plugins/estate-hooks/hooks/input.sh'])
    deleted = commit()
    check('estate-hooks', scope(base, deleted))
    run(['git', 'mv', 'pyproject.toml', 'retired-project.txt'])
    renamed = commit()
    check('linear', scope(deleted, renamed))
    print('PASS: unrelated skip, shared configuration, deletion and rename-away')
    # Relevant range includes the deleted hook; current HEAD is the exact outgoing tree.
    selected_scope = scope(base, renamed)
    output = run(['bash', '.github/scripts/check-push.sh', 'estate-hooks'], expected=23,
                 extra=dict(selected_scope, FIXTURE_EXIT='23'))
    assert 'CALLED:estate-hooks' in output, output
    check('estate-hooks', selected_scope)

    def refused(extra):
        output = run(['bash', '.github/scripts/check-push.sh', 'estate-hooks'], expected=2, extra=extra)
        assert 'BLOCKED: push checks require a clean checkout/worktree' in output, output
        assert 'CALLED:' not in output, output

    refused(scope(base, deleted))
    refused(dict(PRE_COMMIT_REMOTE_NAME='origin', PRE_COMMIT_LOCAL_BRANCH=deleted))
    probe = root / 'plugins/estate-hooks/tests/probe.test.sh'
    saved = probe.read_text()
    probe.write_text(saved + '# dirty\n')
    refused(selected_scope)
    run(['git', 'add', str(probe)])
    probe.write_text(saved)
    refused(selected_scope)  # clean worktree bytes, dirty index
    run(['git', 'reset', '-q', 'HEAD', '--', str(probe)])
    extra = write('plugins/estate-hooks/tests/untracked.test.sh', 'exit 99\n')
    refused(selected_scope)
    extra.unlink()
    write('tool-cache/ordinary', 'ignored\n')
    check('estate-hooks', selected_scope)
    print('PASS: child failure/correction, exact outgoing HEAD, index/worktree/untracked refusal, ignored cache')
    output = run(['bash', '.github/scripts/check-push.sh', 'estate-hooks'], expected=2)
    assert 'range is unavailable' in output and 'CALLED:' not in output, output
    result = subprocess.run(['bash', '.github/scripts/check-push.sh', 'estate-hooks'], cwd=root,
                            env=dict(env, **scope('not-a-ref', renamed)), text=True, capture_output=True)
    assert result.returncode != 0 and 'CALLED:' not in result.stdout, result.stdout
    for component in components:
        check(component, dict(PRE_COMMIT_REMOTE_NAME='origin', PRE_COMMIT_LOCAL_BRANCH='HEAD'))
    print('PASS: absent/unknown range refusal and native first-push selection')
PY
