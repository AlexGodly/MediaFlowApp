import 'package:flutter/material.dart';
import '../../design_system/mediaflow_components.dart';
import '../../services/native_m55_readiness.dart';

/// M55: a frozen, read-only parity and distribution audit.
/// Never performs account reads or writes; never claims CI tests are
/// equivalent to full v410 source and device sign-off.
class NativeM55ReleaseReadinessPanel extends StatelessWidget {
  const NativeM55ReleaseReadinessPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme=Theme.of(context);
    final color=theme.colorScheme;
    return MfPanel(child:Column(
      key:const Key('m55-readiness-panel'),
      crossAxisAlignment:CrossAxisAlignment.stretch,
      children:[
        Row(children:[
          Icon(Icons.fact_check_outlined,color:color.primary),
          const SizedBox(width:9),
          Expanded(child:Text('Website parity & release readiness',
            style:theme.textTheme.titleLarge)),
        ]),
        const SizedBox(height:7),
        Text('MediaFlow v410 baseline · Milestone 55 audit',
          style:theme.textTheme.bodySmall),
        const SizedBox(height:8),
        Text('Production release: BLOCKED',
          key:const Key('m55-release-blocked'),
          style:theme.textTheme.titleMedium?.copyWith(
            fontWeight:FontWeight.bold,color:color.error)),
        Text(NativeM55Readiness.limitation,
          key:const Key('m55-limitations'),
          style:theme.textTheme.bodySmall),
        const SizedBox(height:12),
        Wrap(spacing:8,runSpacing:8,children:[
          _Metric(label:'Inventoried feature surfaces',
            value:NativeM55Readiness.inventorySurfaces),
          _Metric(label:'Feature parity sign-offs',
            value:NativeM55Readiness.certifiedSurfaces),
          _Metric(label:'Inventoried journeys',
            value:NativeM55Readiness.inventoriedJourneys),
          _Metric(label:'Journey sign-offs',
            value:NativeM55Readiness.certifiedJourneys),
          _Metric(label:'Feature domains',
            value:NativeM55Readiness.inventoriedDomains),
          _Metric(label:'Blocking release gates',
            value:NativeM55Readiness.gates.length),
        ]),
        const SizedBox(height:7),
        const Text('These are certification counts, not a percentage of '
          'features implemented. Working Flutter previews and isolated '
          'tests do not establish complete website equivalence.'),
        ExpansionTile(
          key:const Key('m55-release-gates'),
          title:const Text('Why a production release is blocked'),
          subtitle:Text(
            '${NativeM55Readiness.gates.length} unresolved gates'),
          tilePadding:EdgeInsets.zero,
          children:[
            for(final gate in NativeM55Readiness.gates)
              ListTile(
                dense:true,
                contentPadding:EdgeInsets.zero,
                leading:Icon(Icons.lock_outline,
                  color:color.error,size:19),
                title:Text(gate.title),
                subtitle:Text(gate.priority+' · '+gate.id),
              ),
          ],
        ),
        ExpansionTile(
          key:const Key('m55-domain-audit'),
          title:const Text('21-domain source coverage'),
          subtitle:const Text('Inventory exists; full parity is unverified'),
          tilePadding:EdgeInsets.zero,
          children:[
            for(final domain in NativeM55Readiness.domainAudits)
              ListTile(
                dense:true,contentPadding:EdgeInsets.zero,
                title:Text(domain.id.replaceAll('-', ' ')),
                subtitle:Text(
                  '${domain.surfaces} inventoried · '
                  '${domain.certified} certified · '
                  '${domain.journeys} journeys · '
                  '${domain.verifiedJourneys} verified'),
                trailing:const Icon(Icons.info_outline,size:17),
              ),
          ],
        ),
        ExpansionTile(
          key:const Key('m55-future-roadmap'),
          title:const Text('Proposed next development milestones'),
          subtitle:const Text('M56–M70 · not a production rollout'),
          tilePadding:EdgeInsets.zero,
          children:[
            for(final item in NativeM55Readiness.proposedNextMilestones)
              ListTile(dense:true,contentPadding:EdgeInsets.zero,
                title:Text(item)),
          ],
        ),
        const SizedBox(height:7),
        Text('Safety: no Library, History, XP, task, Collection, '
          'Supabase state or upload is changed by this audit.',
          key:const Key('m55-no-writes'),
          style:theme.textTheme.bodySmall),
      ],
    ));
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label,required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) {
    final theme=Theme.of(context);
    return Container(
      constraints:const BoxConstraints(minWidth:130,maxWidth:210),
      padding:const EdgeInsets.symmetric(horizontal:10,vertical:8),
      decoration:BoxDecoration(
        borderRadius:BorderRadius.circular(9),
        color:theme.colorScheme.surfaceContainerHighest),
      child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text('$value',style:theme.textTheme.titleLarge),
          Text(label,style:theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
