#!/usr/bin/env python3
"""Read-only, bounded Swarm task verification; runs on the selected manager."""
import argparse
import json
import subprocess
import sys
import time


def docker(*args):
    result = subprocess.run(
        ['docker', *args], capture_output=True, text=True, timeout=20, check=False
    )
    if result.returncode:
        raise RuntimeError('Docker inspection failed: ' + ' '.join(args[:2]))
    return result.stdout.strip()


def tasks_for(service):
    ids = docker('service', 'ps', '--quiet', '--no-trunc', service).splitlines()
    return json.loads(docker('inspect', '--type', 'task', *ids)) if ids else []


def migration_status(tasks):
    if not tasks:
        return False
    # Restart policy none must produce exactly one task. Never accept an old success.
    if len(tasks) != 1:
        raise RuntimeError('Migration has multiple tasks; refusing ambiguous result')
    status = tasks[0]['Status']
    state = status['State']
    if state == 'complete':
        if status.get('ContainerStatus', {}).get('ExitCode') != 0:
            raise RuntimeError('Migration completed without a verified zero exit code')
        return True
    if state in {'failed', 'rejected', 'shutdown', 'orphaned', 'remove'}:
        raise RuntimeError('Migration task ended in ' + state)
    return False


def service_converged(service, tasks, expected_image=None):
    update = service.get('UpdateStatus', {}).get('State', '')
    if update in {'paused', 'rollback_started', 'rollback_paused', 'rollback_completed'}:
        raise RuntimeError('Application update failed: ' + update)
    if update and update != 'completed':
        return False
    expected = service['Spec']['Mode']['Replicated']['Replicas']
    image = service['Spec']['TaskTemplate']['ContainerSpec']['Image']
    if expected < 1:
        raise RuntimeError('Application has no requested replicas')
    if expected_image and image.split('@', 1)[0] != expected_image:
        raise RuntimeError('Application is not using the requested build image')
    active = [t for t in tasks if t['DesiredState'] == 'running']
    return len(active) == expected and all(
        t['Status']['State'] == 'running'
        and t['Spec']['ContainerSpec']['Image'] == image for t in active
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('mode', choices=['migration', 'convergence', 'drained'])
    parser.add_argument('--timeout', type=int, required=True)
    parser.add_argument('--image', help='Expected application image tag for convergence')
    parser.add_argument('services', nargs='+')
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error('--timeout must be positive')
    deadline = time.monotonic() + args.timeout
    while time.monotonic() < deadline:
        if args.mode == 'migration':
            ready = migration_status(tasks_for(args.services[0]))
        elif args.mode == 'drained':
            ready = all(t['Status']['State'] in {'complete', 'failed', 'rejected',
                        'shutdown', 'orphaned', 'remove'}
                        for t in tasks_for(args.services[0]))
        else:
            ready = all(
                service_converged(
                    json.loads(docker('service', 'inspect', name))[0], tasks_for(name), args.image
                ) for name in args.services
            )
        if ready:
            print(args.mode + ' verified')
            return 0
        time.sleep(3)
    raise RuntimeError(args.mode + ' timed out; inspect the retained service tasks')


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
