#!/usr/bin/env python3
"""Offline Sydney payload exporter. Never calls AWS or launches instances.

Default output retains DryRun=true. Real-launch export requires separate owner
host-specific, expiring spending approval bound to the reviewed request.
"""
import argparse
import copy
from datetime import datetime, timezone, timedelta
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


HOSTS=('validator-1','validator-2')
# Immutable review anchors: changing any launch field requires source review.
REQUEST_DIGESTS=dict(zip(HOSTS,(
    'd585f3f6eb699f4c02def92de290533d5fb9588e56332420217d3e023c1fbce4',
    '7011ea2d7885584e48371283f1d828699db7d68a8a5eb52609d1bc674964f2f3')))


def approval_binding(m, host, request):
    return dict(host=host,accountId=m['accountId'],region=m['region'],
        instanceType=request['InstanceType'],securityGroupIds=request['NetworkInterfaces'][0]['Groups'],
        instanceProfileArn=request['IamInstanceProfile']['Arn'],requestSha256=digest(request))


def approval_valid(m, host, request, now):
    approval=m.get('hostLaunchApprovals',{}).get(host,{})
    if not isinstance(approval,dict):raise ValueError('Malformed host approval')
    try:
        issued=datetime.fromisoformat(approval['issuedAt'])
        expires=datetime.fromisoformat(approval['expiresAt'])
        valid=(issued.tzinfo is not None and expires.tzinfo is not None
            and issued<=now<expires and timedelta(0)<expires-issued<=timedelta(hours=24))
    except (KeyError,ValueError,TypeError):valid=False
    if not (valid and approval.get('approved') is True
        and isinstance(approval.get('reference'),str) and approval['reference'].strip()
        and approval.get('binding')==approval_binding(m,host,request)
        and m.get('awsLaunchApprovals',{}).get('accountVerified') is True):
        raise ValueError('BLOCKED: '+host+' requires exact host-specific spending approval, reference and valid <=24h expiry')


def prepare(m, real_launch=False, host=None, now=None):
    public_only(m)
    if host is not None and host not in HOSTS:raise ValueError('Explicit supported host required')
    baseline=json.loads(MANIFEST.read_text())
    for key in ('accountId','operatorProfile','region','deploymentProfile','target','ec2Preparation'):
        if m.get(key)!=baseline[key]:raise ValueError('Reviewed Sydney design mismatch: '+key)
    if selected_profile(m)['instanceType']!='m6a.xlarge':raise ValueError('Headroom profile required')
    rows=m.get('hosts',[])
    if len(rows)!=2 or {h.get('name') for h in rows}!=set(HOSTS):raise ValueError('Exactly two uniquely named hosts required')
    requests=dict(zip(HOSTS,reviewed_requests()))
    selected=(host,) if host else HOSTS
    result=[]
    for name in selected:
        h=next(h for h in rows if h['name']==name)
        expected=next(h for h in baseline['hosts'] if h['name']==name)
        request=requests[name]
        if digest(request)!=REQUEST_DIGESTS[name]:raise ValueError('Reviewed launch request digest mismatch: '+name)
        for key in ('region','availabilityZone','subnetId','securityGroupIds','instanceProfileArn'):
            if h.get(key)!=expected[key]:raise ValueError('Reviewed Sydney host mismatch: '+key)
        if any(h.get(k) for k in ('instanceId','dataVolumeId','rootVolumeId','launchRecord')):
            raise ValueError('Existing host/volume/launch record: refuse replacement or duplicate launch: '+name)
        if request.get('DryRun') is not True:raise ValueError('Evidence must remain dry-run only')
        r=copy.deepcopy(request)
        if real_launch:
            approval_valid(m,name,request,now or datetime.now(timezone.utc))
            r['DryRun']=False
            # Stable across approval renewal; never turn a retry into a new instance.
            r['ClientToken']=digest(approval_binding(m,name,request))
        result.append(r)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',type=Path,required=True)
    p.add_argument('--output-dir',type=Path,required=True)
    p.add_argument('--approved-real-launch',action='store_true')
    p.add_argument('--host',choices=HOSTS,help='Export only this host; omitted means both, each independently approved')
    a=p.parse_args()
    try:
        m=json.loads(a.manifest.read_text());requests=prepare(m,a.approved_real_launch,a.host)
        # No overwrite: archived requests/results must remain immutable.
        a.output_dir.mkdir(parents=True,exist_ok=False)
        commands=[]
        for name,r in zip((a.host,) if a.host else HOSTS,requests):
            path=(a.output_dir/f'{name}.json').resolve();path.write_text(json.dumps(r,indent=2)+'\n')
            command=['aws','--profile',m['operatorProfile'],'--region',m['region'],'ec2','run-instances','--cli-input-json','file://'+str(path)]
            if not a.approved_real_launch:command.append('--dry-run')
            commands.append(shlex.join(command))
        names=(a.host,) if a.host else HOSTS
        evidence=dict(zip(HOSTS,reviewed_requests()))
        bindings={name:approval_binding(m,name,evidence[name]) for name in names}
        print(json.dumps({'executed':False,'realLaunchExport':a.approved_real_launch,
            'selectedHosts':list(names),'requestBindings':bindings,'commands':commands},indent=2))
    except (ValueError,KeyError,OSError) as e:p.exit(1,str(e)+'\n')

if __name__=='__main__':main()
