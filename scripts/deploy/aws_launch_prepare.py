#!/usr/bin/env python3
"""Offline Sydney payload exporter. Never calls AWS or launches instances.

Default output retains DryRun=true. Real-launch export requires separate owner
spending approval, a reference and digest binding to the reviewed request pair.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import shlex
from aws_pilot import ROOT, public_only, selected_profile

EVIDENCE = ROOT/'deploy/aws/sydney-authorization'
MANIFEST = ROOT/'deploy/aws/sydney.deployment.review.json'


def reviewed_requests():
    return [json.loads((EVIDENCE/f'validator-{n}.run-instances.dry-run.json').read_text()) for n in (1, 2)]


def digest(requests):
    return hashlib.sha256(json.dumps(requests, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def prepare(m, real_launch=False):
    public_only(m)
    baseline=json.loads(MANIFEST.read_text())
    # Resource/design changes require another review, never a silent fallback.
    for key in ('accountId','operatorProfile','region','deploymentProfile','target'):
        if m.get(key)!=baseline[key]:raise ValueError('Reviewed Sydney design mismatch: '+key)
    if selected_profile(m)['instanceType']!='m6a.xlarge':raise ValueError('Headroom profile required')
    requests=reviewed_requests()
    for h, expected, request in zip(m['hosts'], baseline['hosts'], requests):
        for key in ('name','region','availabilityZone','subnetId','securityGroupIds','instanceProfileArn'):
            if h.get(key)!=expected[key]:raise ValueError('Reviewed Sydney host mismatch: '+key)
        if h.get('instanceId') or h.get('dataVolumeId') or h.get('rootVolumeId'):
            raise ValueError('Existing host/volume: refuse replacement or duplicate launch')
        if request.get('DryRun') is not True:raise ValueError('Evidence must remain dry-run only')
    if len(m['hosts'])!=2:raise ValueError('Exactly two hosts required')
    approval=m.get('awsLaunchApprovals',{})
    review=m.get('ec2Preparation',{})
    if real_launch and not (approval.get('accountVerified') is True and approval.get('ec2LaunchAuthorized') is True
        and isinstance(review.get('spendingApprovalReference'),str) and review['spendingApprovalReference'].strip()
        and review.get('launchPayloadsSha256')==digest(requests)):
        raise ValueError('BLOCKED: separate owner real EC2 spending/instance creation approval, reference and reviewed payload digest required')
    result=copy.deepcopy(requests)
    if real_launch:
        for n,r in enumerate(result,1):
            r['DryRun']=False
            # Stable idempotency token binds this approved pair and approval record.
            r['ClientToken']=hashlib.sha256((digest(requests)+review['spendingApprovalReference']+str(n)).encode()).hexdigest()
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',type=Path,required=True)
    p.add_argument('--output-dir',type=Path,required=True)
    p.add_argument('--approved-real-launch',action='store_true')
    a=p.parse_args()
    try:
        m=json.loads(a.manifest.read_text());requests=prepare(m,a.approved_real_launch)
        # No overwrite: archived requests/results must remain immutable.
        a.output_dir.mkdir(parents=True,exist_ok=False)
        commands=[]
        for n,r in enumerate(requests,1):
            path=(a.output_dir/f'validator-{n}.json').resolve();path.write_text(json.dumps(r,indent=2)+'\n')
            command=['aws','--profile',m['operatorProfile'],'--region',m['region'],'ec2','run-instances','--cli-input-json','file://'+str(path)]
            if not a.approved_real_launch:command.append('--dry-run')
            commands.append(shlex.join(command))
        print(json.dumps({'executed':False,'realLaunchExport':a.approved_real_launch,'reviewedPayloadsSha256':digest(reviewed_requests()),'commands':commands},indent=2))
    except (ValueError,KeyError,OSError) as e:p.exit(1,str(e)+'\n')

if __name__=='__main__':main()
