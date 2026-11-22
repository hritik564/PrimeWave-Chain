"""Offline DIRECT_MAINNET gates. Reads public evidence only; cannot sign or execute.

PASS means the supplied, owner-reviewed evidence validates, not authenticity of
arbitrary operator files. Capture genuine observations; synthetic fixtures are
only for tests. Every file is digest-bound, every approval is stage-specific.
"""
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import hashlib
import json
from pathlib import Path
import re
STAGES = ('PRE_MAINNET_LAUNCH', 'POST_MAINNET_ACCEPTANCE')
OPERATIONS = ('createSubnet', 'createChain', 'convertSubnet', 'initializeManager', 'activateValidators', 'nativeTransfer', 'feeDistribution', 'recoveryDrill')
PREVIOUS = {'createSubnet': (), 'createChain': ('createSubnet',), 'convertSubnet': ('createSubnet', 'createChain'), 'initializeManager': ('createSubnet', 'createChain', 'convertSubnet'), 'activateValidators': ('initializeManager',), 'nativeTransfer': ('activateValidators',), 'feeDistribution': ('nativeTransfer',), 'recoveryDrill': ('feeDistribution',)}

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()

def read(ref, aws):
    if not isinstance(ref, dict):
        raise ValueError('digest-bound public evidence reference required')
    path = Path(ref.get('path') or '')
    if path.suffix != '.json' or any(part in path.parts for part in ('.aws', '.ssh', '.gnupg', 'staking')) or not path.is_absolute() or any((p.is_symlink() for p in (path, *path.parents))) or (not path.is_file()) or (path.stat().st_size > 16 * 1024 * 1024):
        raise ValueError('existing absolute non-symlink public evidence file <=16MiB required')
    raw = path.read_bytes()
    if hashlib.sha256(raw).hexdigest() != ref.get('sha256'):
        raise ValueError('evidence file digest mismatch')
    value = json.loads(raw)
    aws.public_only(value)
    return (value, path)

def positive(value):
    try:
        return isinstance(value, str) and Decimal(value).is_finite() and (Decimal(value) > 0)
    except InvalidOperation:
        return False

def address(value):
    return isinstance(value, str) and re.fullmatch('0x[0-9a-fA-F]{40}', value) and (int(value, 16) > 0)

def bound(value, m):
    e = m['environments']['mainnet']
    return value.get('networkId') == 1 and value.get('chainId') == e['evmChainId'] and (value.get('genesisSha256') == e['genesisSha256'])

def approval_ok(approval, binding, aws):
    if not isinstance(approval, dict):
        return False
    try:
        issued = datetime.fromisoformat(approval['issuedAt'])
        expires = datetime.fromisoformat(approval['expiresAt'])
        now = datetime.now(timezone.utc)
        valid = issued <= now < expires and 0 < (expires - issued).total_seconds() <= 86400
    except (KeyError, TypeError, ValueError):
        valid = False
    return valid and approval.get('approved') is True and bool(approval.get('reference')) and (approval.get('binding') == binding)

def readiness(m, stage, operation, aws):
    errors = []
    e = m['environments']['mainnet']
    r = m.get('mainnetReadiness', {})

    def need(ok, message):
        if not ok:
            errors.append(message)

    def check(label, fn):
        try:
            fn()
        except (ValueError, KeyError, TypeError, OSError, AssertionError) as error:
            errors.append(label + ': ' + (str(error) or 'validation failed'))
    need(m.get('deploymentStrategy') == 'DIRECT_MAINNET', 'explicit DIRECT_MAINNET strategy required')
    need(stage in STAGES, 'explicit supported readiness stage required')
    need(e.get('avalancheNetworkId') == 1, 'Avalanche Mainnet Primary Network ID1 required')
    errors.extend(aws.manifest_errors(m))
    need(m.get('awsLaunchApprovals', {}).get('accountVerified') is True, 'verified AWS account required')
    need(m.get('allocationPolicy') == 'C00' and m.get('nativeSupplyPW') == 100000000 and (m.get('nativeMinterEnabled') is False) and (m.get('feeSplitBps') == dict(validators=7000, treasury=2000, burn=1000)), 'locked C00 supply/allocation/fee policy mismatch')
    for h in m.get('hosts', []):

        def host_check(h=h):
            refs = r.get('hostEvidence', {})[h['name']]
            cloud, _ = read(refs['cloud'], aws)
            local, _ = read(refs['local'], aws)
            require(local.get('environment') == 'mainnet', 'production host evidence required')
            gate = aws.host_gate(m, h['name'], cloud, local)
            require(gate['status'] == 'PASS', '; '.join(gate['blockers']))
            operational, _ = read(refs.get('operations'), aws)
            require(aws.fresh(operational.get('observedAt')), 'fresh operational host evidence required')
            require(all((operational.get(k) == h.get(k) for k in ('instanceId', 'dataVolumeId', 'filesystemUuid'))), 'operational host storage identity mismatch')
            identity = operational.get('publicIdentity', {})
            expected = e['identities'][h['name']]
            require(all((identity.get(k) == expected.get(k) and identity.get(k) for k in ('nodeId', 'blsPublicKey', 'proofOfPossession', 'stakingCertificateSha256'))), 'verified public host identity differs')
            require(operational.get('certificateSha256') == expected.get('stakingCertificateSha256'), 'actual public certificate hash required')
            require(operational.get('identityFilesPrivate') is True and operational.get('productionOnly') is True, 'identity permissions/custody verification required')
            require(operational.get('alertDeliveryVerified') is True and operational.get('alertEventId'), 'actual monitoring alert delivery required')
            roots = cloud.get('rootVolumes', [])
            require(len(roots) == 1 and roots[0].get('VolumeId') == h['rootVolumeId'] and (roots[0].get('Encrypted') is True) and (roots[0].get('Size', 0) >= 32) and (roots[0].get('VolumeType') == 'gp3'), 'encrypted >=32GiB gp3 root evidence required')
        check('host ' + h['name'], host_check)
    check('production identities/custody', lambda: identities(m, e))
    if stage == 'POST_MAINNET_ACCEPTANCE':
        check('production acceptance', lambda: post_acceptance(m, r, aws))
    else:
        check('chain/genesis/artifacts', lambda: artifacts(m, r, aws))
        check('off-host recovery and incident procedures', lambda: recovery(m, r, aws))
        check('bounded commissioning plan', lambda: commissioning(m, r, aws))
        check('transaction plans', lambda: transaction_plans(m, r, aws))
        check('selected operation ' + str(operation), lambda: operation_check(m, r, operation, aws))
    return dict(status='BLOCKED' if errors else 'PASS', stage=stage, operation=operation, strategy=m.get('deploymentStrategy'), blockers=errors, readOnly=True, signing=False, broadcastReady=False, awsMutations=False, manifestSha256=sha(m), scope='OFFLINE_EVIDENCE_REVIEW_ONLY; not signing, broadcasting, host start or public access authorization')

def identities(m, e):
    require(e.get('approvals', {}).get('identityCreation') is True, 'production identity ceremony authorization record required')
    p = e['genesisPublic']
    require(p.get('publicAddressesReviewed') is True and p.get('custodyProposalApproved') is True, 'production custody approval required')
    ids = e['identities']
    require(set(ids) == {'validator-1', 'validator-2'}, 'two production identity records required')
    for key, pattern in [('nodeId', 'NodeID-[1-9A-HJ-NP-Za-km-z]{20,50}'), ('blsPublicKey', '0x[0-9a-fA-F]{96}'), ('proofOfPossession', '0x[0-9a-fA-F]{192}'), ('stakingCertificateSha256', '[0-9a-f]{64}')]:
        values = [i.get(key) for i in ids.values()]
        require(all((isinstance(v, str) and re.fullmatch(pattern, v) for v in values)) and len(set(values)) == 2, 'distinct production ' + key + ' verification required')
        other = {i.get(key) for i in m.get('environments', {}).get('fuji', {}).get('identities', {}).values()}
        require(not set(values) & other, 'never reuse optional Fuji identities')
    for i in ids.values():
        require(i.get('environment') == 'mainnet' and i.get('productionOnly') is True, 'production-only identity attestation required')

    def custody(env):
        p = env.get('genesisPublic', {})
        return {x.lower() for x in [*p.get('allocationAddresses', {}).values(), *p.get('contracts', {}).values(), p.get('governanceProposer'), *p.get('emergencySigners', []), env.get('proxyAdmin')] if isinstance(x, str)}
    require(not custody(e) & custody(m.get('environments', {}).get('fuji', {})), 'test custody cannot authorize Mainnet')

def artifacts(m, r, aws):
    import chain_id
    import genesis_candidate
    e = m['environments']['mainnet']
    require(e.get('chainIdApproved') is True, 'Chain ID approval required')
    decision, _ = read(r.get('chainApproval'), aws)
    _, registry = read(r.get('registry'), aws)
    require(chain_id.approved(decision, registry) == e.get('evmChainId'), 'fresh exact Chain ID collision review required')
    require(e['evmChainId'] != m.get('environments', {}).get('fuji', {}).get('evmChainId'), 'Mainnet and optional Fuji Chain IDs must differ')
    require(e.get('genesisApproved') is True, 'exact final genesis approval required')
    genesis, _ = read(r.get('genesis'), aws)
    construction, _ = read(r.get('construction'), aws)
    require(construction['public'] == e['genesisPublic'], 'public custody and constructor bundle mismatch')
    result = genesis_candidate.materialize(construction['public'], construction['exported'], construction['base'])
    require(result['genesis'] == genesis and result['genesisSha256'] == e.get('genesisSha256'), 'constructor-state/final genesis digest mismatch')
    require(genesis['config']['chainId'] == e['evmChainId'], 'genesis Chain ID differs')
    review, _ = read(r.get('securityReview'), aws)
    require(bound(review, m) and review.get('ownerReviewed') is True and review.get('reference'), 'exact artifact security review required')
    require(review.get('constructionSha256') == sha(construction), 'constructor artifact review binding required')
    require(review.get('managerArtifactSha256') == e.get('managerArtifactSha256') and re.fullmatch('[0-9a-f]{64}', e.get('managerArtifactSha256') or ''), 'manager artifact digest required')
    artifact, _ = read(r.get('managerArtifact'), aws)
    require(sha(artifact) == e['managerArtifactSha256'], 'actual manager artifact mismatch')
    codes = artifact.get('runtimeBytecode', {})
    require(set(codes) == {e.get(k) for k in ('managerProxy', 'managerImplementation', 'managerLibrary')}, 'manager/proxy/library runtime bytecode bundle required')
    allocations = {a.lower(): v for a, v in genesis['alloc'].items()}
    for target, code in codes.items():
        require(re.fullmatch('0x(?:[0-9a-fA-F]{2})+', code or '') and allocations.get(target.lower(), {}).get('code') == code, 'compiled runtime/genesis bytecode mismatch')
    vm, _ = read(r.get('vmCompatibility'), aws)
    require(bound(vm, m) and vm.get('ownerReviewed') is True and vm.get('reference'), 'exact final genesis isolated VM evidence required')
    require(vm.get('avalancheGo') == '1.15.1' and vm.get('subnetEvm') == '1.15.1' and (vm.get('pluginProtocol') == 46), 'pinned node/VM compatibility required')
    require(vm.get('handshakePassed') is True and vm.get('genesisAccepted') is True and (vm.get('initializationTestsPassed') is True), 'isolated final-genesis/manager initialization tests required')
    for flag in ('managerBootstrapReviewed', 'managerInitializationReviewed', 'genesisForksReviewed'):
        require(e.get(flag) is True and review.get(flag) is True, flag + ' required')
    require(review.get('uninitializedProxyCallable') is False and review.get('bootstrapMode') in ('subnet-bound-genesis', 'owner-atomic-upgrade-initialize'), 'publicly callable uninitialized proxy forbidden')
    require(all((address(e.get(k)) for k in ('managerProxy', 'managerImplementation', 'managerLibrary', 'proxyAdmin'))), 'actual manager/library/proxy/admin addresses required')
    require(e['managerProxy'].lower() == e['genesisPublic']['managerAddress'].lower(), 'manager genesis binding differs')
    require(len({e[k].lower() for k in ('managerProxy', 'managerImplementation', 'managerLibrary', 'proxyAdmin')}) == 4, 'manager role separation required')
    gov = review['governance']
    signers = gov['signers']
    threshold = gov['threshold']
    require(len(signers) >= 3 and all((address(a) for a in signers)) and (len(set((a.lower() for a in signers))) == len(signers)), 'distinct production governance signers required')
    require(type(threshold) is int and 2 <= threshold <= len(signers) and (gov.get('timelockSeconds', 0) >= 172800), 'reviewed multisig and >=48h timelock required')
    require(address(gov.get('owner')) and gov['owner'].lower() == e['proxyAdmin'].lower(), 'proxy governance owner differs')
    weights = review['validatorWeights']
    require(set(weights) == set(e['identities']) and all((type(v) is int and v > 0 for v in weights.values())), 'explicit validator weights required')

def recovery(m, r, aws):
    ops = m.get('operations', {})
    require(ops.get('offHostRecoveryVerified') is True, 'tested off-host recovery required')
    value, _ = read(r.get('recovery'), aws)
    require(sha(value) == ops.get('recoveryEvidenceSha256'), 'off-host recovery evidence digest differs')
    require(value.get('accountId') == m['accountId'] and value.get('region') == m['region'], 'recovery account/region mismatch')
    require(value.get('procedureTestPassed') is True and value.get('singleActiveIdentityFencingVerified') is True and value.get('reference'), 'tested procedure and identity fencing evidence required')
    require(value.get('containsProductionKeys') is False, 'public recovery evidence only')
    incident, _ = read(r.get('incidentResponse'), aws)
    require(incident.get('ownerApproved') is True and incident.get('reference') and (incident.get('twoValidatorHaltAccepted') is True), 'reviewed non-resilient pilot incident response required')
    for k in ('stopCriteria', 'escalationContact', 'rollbackProcedure', 'noDatabaseReset', 'noDuplicateIdentity'):
        require(incident.get(k), 'incident prerequisite missing: ' + k)

def commissioning(m, r, aws):
    plan, _ = read(r.get('commissioningPlan'), aws)
    require(bound(plan, m) and plan.get('ownerReviewed') is True and plan.get('reference'), 'bounded Mainnet commissioning plan required')
    require(type(plan.get('maximumTransfers')) is int and 1 <= plan['maximumTransfers'] <= 10, 'commissioning <=10 bounded transfers required')
    require(type(plan.get('maximumDurationSeconds')) is int and 0 < plan['maximumDurationSeconds'] <= 3600, 'commissioning <=1h duration required')
    require(positive(plan.get('maximumNativePW')) and positive(plan.get('maximumGasPW')), 'explicit PW amount/gas ceilings required')
    require(plan.get('gasSourceRole') in ('liquidity', 'treasury', 'team', 'rewards', 'presale1', 'presale2', 'presale3'), 'gas spend must use an existing C00 allocation')
    for k in ('productionRiskAccepted', 'haltOnMismatch', 'haltOnResourcePressure', 'alertDeliveryRequired', 'recoveryRequiredBeforePublicAccess'):
        require(plan.get(k) is True, 'commissioning risk/stop control missing: ' + k)
    if m['deploymentProfile'] == 'aws-m6a-large-low-throughput':
        risk = m.get('smallProfileProduction', {})
        require(risk.get('ownerApproved') is True and risk.get('physicalCoreExceptionAccepted') is True, 'small-profile physical-core risk acceptance required')

def transaction_plans(m, r, aws):
    e = m['environments']['mainnet']
    require(positive(e.get('pChainBudgetAVAX')) and positive(e.get('validatorBalanceAVAX')), 'explicit Mainnet funding/validator AVAX budgets required')
    require(re.fullmatch('P-avax1[0-9a-z]{30,90}', e.get('pChainFundingAddress') or ''), 'production P-Chain funding address required')
    require(e.get('signerKeystoreAlias') and e.get('pwGasSourceRole') and e.get('signatureAggregatorUrl'), 'production signer/gas source/local aggregator required')
    from urllib.parse import urlsplit
    aggregator = urlsplit(e['signatureAggregatorUrl'])
    require(aggregator.scheme == 'http' and aggregator.hostname == '127.0.0.1' and aggregator.port and (not aggregator.username) and (not aggregator.password), 'private operator aggregator required')
    for operation in OPERATIONS:
        item = r.get('transactions', {}).get(operation, {})
        value, _ = read(item.get('request'), aws)
        require(value.get('transactionCount') == 1 and bound(value, m) and (value.get('operation') == operation), 'exact network/operation transaction plan required: ' + operation)
        require(value.get('reviewed') is True and value.get('reference') and value.get('parameters'), 'reviewed parameters required: ' + operation)
        require(re.fullmatch('pw-mainnet-[A-Za-z0-9_-]+', value.get('signerAlias') or ''), 'production signer alias required')
        require(positive(value.get('maximumFeeAVAX')) and positive(value.get('maximumTotalSpendAVAX')), 'explicit AVAX fee/total-spend ceilings required')
        require(Decimal(value['maximumFeeAVAX']) <= Decimal(value['maximumTotalSpendAVAX']), 'fee exceeds total budget')

def operation_check(m, r, operation, aws):
    require(operation in OPERATIONS, 'explicit supported Mainnet operation required')
    item = r.get('transactions', {}).get(operation, {})
    value, _ = read(item.get('request'), aws)
    binding = dict(operation=operation, networkId=1, accountId=m['accountId'], region=m['region'], requestSha256=sha(value))
    require(approval_ok(item.get('approval'), binding, aws), 'separate exact operation/signer/budget owner approval required')
    if operation in ('convertSubnet', 'initializeManager', 'activateValidators'):
        review, _ = read(r.get('securityReview'), aws)
        require(value['parameters'].get('managerProxy') == m['environments']['mainnet']['managerProxy'], 'selected manager/proxy binding required')
        require(value['parameters'].get('validatorWeights') == review['validatorWeights'], 'selected validator weights binding required')
    if PREVIOUS[operation]:
        evidence, _ = read(r.get('executionEvidence'), aws)
        require(bound(evidence, m), 'production execution evidence required')
        for previous in PREVIOUS[operation]:
            record = evidence.get('operations', {}).get(previous, {})
            request, _ = read(r['transactions'][previous]['request'], aws)
            require(record.get('requestSha256') == sha(request) and record.get('accepted') is True and record.get('transactionId'), 'accepted prior operation receipt required: ' + previous)
        if operation in ('createChain', 'convertSubnet', 'initializeManager', 'activateValidators', 'nativeTransfer', 'feeDistribution', 'recoveryDrill'):
            require(value['parameters'].get('subnetId') == m['environments']['mainnet'].get('subnetId') and value['parameters'].get('subnetId'), 'selected request must bind actual Subnet ID')
        if operation in ('convertSubnet', 'initializeManager', 'activateValidators', 'nativeTransfer', 'feeDistribution', 'recoveryDrill'):
            require(value['parameters'].get('blockchainId') == m['environments']['mainnet'].get('blockchainId') and value['parameters'].get('blockchainId'), 'selected request must bind actual Blockchain ID')
            require(evidence.get('subnetId') == m['environments']['mainnet'].get('subnetId') and evidence.get('subnetId'), 'actual subnet binding required')
            require(evidence.get('blockchainId') == m['environments']['mainnet'].get('blockchainId') and evidence.get('blockchainId'), 'actual blockchain binding required')
        if operation in ('nativeTransfer', 'feeDistribution', 'recoveryDrill'):
            require(evidence.get('consensusHealthy') is True and evidence.get('managerOwnershipVerified') is True, 'running consensus and manager ownership prerequisites required')

def post_acceptance(m, r, aws):
    artifacts(m, r, aws)
    commissioning(m, r, aws)
    recovery(m, r, aws)
    transaction_plans(m, r, aws)
    require(not aws.small_workload_errors(m, environment='mainnet'), 'actual Mainnet smaller-profile performance evidence required')
    e = m['environments']['mainnet']
    value, _ = read(r.get('postEvidence'), aws)
    require(bound(value, m) and aws.fresh(value.get('observedAt')), 'fresh production evidence required')
    require(value.get('blockchainId') == e.get('blockchainId') and value.get('blockchainId'), 'actual Blockchain ID required')
    require(value.get('genesisBlockHash') == e.get('genesisBlockHash') and value.get('genesisBlockHash'), 'actual genesis block hash required')
    nodes = value['validators']
    require(set(nodes) == set(e['identities']), 'both validators required')
    for name, node in nodes.items():
        h = aws.host_named(m, name)
        require(node.get('instanceId') == h['instanceId'] and node.get('nodeId') == e['identities'][name]['nodeId'], 'running production identity mismatch')
        require(node.get('running') is True and node.get('pChainHealthy') is True and (node.get('pChainSynced') is True), 'live validator and P-Chain checks required')
        require(node.get('registrationActive') is True and type(node.get('weight')) is int and (node['weight'] > 0), 'registered validator/weight required')
        require(node.get('startAcceptedHeight', -1) >= 0 and node.get('endAcceptedHeight', 0) > node['startAcceptedHeight'], 'advancing accepted blocks required')
        require(node.get('alertDelivered') is True and node.get('monitoringHealthy') is True, 'actual alert delivery required')
        for key, ceiling in [('cpuMeanPercent', 70), ('cpuP95Percent', 90), ('memoryPeakPercent', 80), ('diskPeakUsedPercent', 80), ('iopsPeakPercentOfProvisioned', 80)]:
            require(type(node.get(key)) in (int, float) and 0 <= node[key] < ceiling, 'resource pressure requires operational intervention: ' + key)
        require(all((node.get(k) == 0 for k in ('oomKills', 'nodeRestarts', 'swapInBytes', 'swapOutBytes'))), 'commissioning restart/OOM/swap intervention required')
        require(node.get('minimumNetworkMbps', 0) >= 25 and 0 < node.get('confirmationP95Ms', 0) <= 5000, 'network/confirmation acceptance failed')
    left, right = nodes.values()
    require(left.get('receipts') and left['receipts'] == right.get('receipts'), 'actual matching receipt arrays required')
    require(left.get('receiptSetSha256') == sha(left['receipts']), 'receipt set digest mismatch')
    actual_receipts = {receipt['transactionHash']: receipt for receipt in left['receipts']}
    for key in ('genesisBlockHash', 'acceptedBlockHeight', 'acceptedBlockHash', 'receiptSetSha256'):
        require(left.get(key) and left.get(key) == right.get(key), 'matching node block/receipt evidence required: ' + key)
    require(left['genesisBlockHash'] == e['genesisBlockHash'], 'validator genesis differs')
    review, _ = read(r.get('securityReview'), aws)
    require(all((nodes[n]['weight'] == review['validatorWeights'][n] for n in nodes)), 'registration weight differs from approved weight')
    receipts = value['nativeTransfers']
    require(receipts, 'real native transfer receipts required')
    plan, _ = read(r.get('commissioningPlan'), aws)
    require(1 <= len(receipts) <= plan['maximumTransfers'], 'bounded native transfer count exceeded')
    require(0 < value.get('durationSeconds', 0) <= plan['maximumDurationSeconds'], 'commissioning duration differs')
    total = 0
    gas_total = 0
    for tx in receipts:
        require(tx.get('status') == 1 and tx.get('transactionHash') and tx.get('blockHash') and (tx.get('bothNodesMatch') is True), 'accepted matching native receipt required')
        receipt = actual_receipts.get(tx['transactionHash'], {})
        require(receipt.get('status') == 1 and receipt.get('blockHash') == tx['blockHash'] and (receipt.get('gasUsed') == tx['gasUsed']) and (receipt.get('effectiveGasPrice') == tx['effectiveGasPrice']), 'native receipt/gas evidence mismatch')
        require(type(tx.get('beforeBlock')) is int and type(tx.get('afterBlock')) is int and (tx['afterBlock'] > tx['beforeBlock']), 'fixed-block balance observations required')
        amount = int(tx['valueWei'])
        gas = int(tx['gasUsed']) * int(tx['effectiveGasPrice'])
        require(amount > 0 and gas > 0, 'validation failed')
        require(int(tx['senderBefore']) - int(tx['senderAfter']) == amount + gas, 'sender/gas accounting mismatch')
        require(int(tx['recipientAfter']) - int(tx['recipientBefore']) == amount, 'recipient accounting mismatch')
        total += amount
        gas_total += gas
    require(total <= Decimal(plan['maximumNativePW']) * 10 ** 18 and gas_total <= Decimal(plan['maximumGasPW']) * 10 ** 18, 'commissioning amount/gas exceeded')
    fee = value['feeAccounting']
    amount = int(fee['distributableWei'])
    require(amount > 0 and fee.get('receiptStatus') == 1 and fee.get('transactionHash') and (fee.get('bothNodesMatch') is True), 'real FeeDistributor receipt required')
    require(actual_receipts.get(fee['transactionHash'], {}).get('status') == 1, 'actual FeeDistributor receipt missing')
    validators = amount * 70 // 100
    treasury = amount * 20 // 100
    require([int(fee[k]) for k in ('validatorDeltaWei', 'treasuryDeltaWei', 'burnDeltaWei')] == [validators, treasury, amount - validators - treasury], '70/20/10 fee accounting mismatch')
    require(fee.get('destinationsVerified') is True and fee.get('concurrentGasReconciled') is True, 'fee destinations/concurrent gas reconciliation required')
    drill = value['recovery']
    restored, _ = read(r.get('productionRecovery'), aws)
    require(bound(restored, m) and drill.get('evidenceSha256') == sha(restored), 'actual production recovery evidence binding required')
    require(restored.get('ownerReviewed') is True and restored.get('reference') and restored.get('oldHostFenced') is True, 'reviewed fenced production restoration required')
    require(restored.get('identities') == e['identities'], 'restored production identities must match exactly')
    require(drill.get('restoredSameIdentity') is True and drill.get('databasePreserved') is True and (drill.get('fencingVerified') is True) and drill.get('evidenceSha256'), 'actual controlled production recovery required')
    require(approval_ok(r.get('finalAcceptance'), dict(stage='POST_MAINNET_ACCEPTANCE', networkId=1, evidenceSha256=sha(value)), aws), 'final production acceptance owner approval required')
