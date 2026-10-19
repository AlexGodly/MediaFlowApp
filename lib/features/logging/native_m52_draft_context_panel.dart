import 'package:flutter/material.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_editing_workspace.dart';
import '../../services/native_m52_task_draft_context.dart';
import 'native_m53_completion_evidence_panel.dart';

/// Presentation only. Never pre-populates, converts, stages, saves or
/// advances a native or website draft. The existing editors own those fields.
class NativeM52DraftContextPanel extends StatelessWidget {
  const NativeM52DraftContextPanel({
    super.key,required this.contextToken,required this.catalog,
    required this.titleId,required this.currentOwnerId,
    this.workspace,this.method='review',this.showCompletionEvidence=true,
  });
  final NativeM52TaskDraftContext contextToken;
  final MediaFlowCatalog catalog;
  final String titleId,currentOwnerId,method;
  final NativeEditingWorkspace? workspace;
  final bool showCompletionEvidence;

  static String _amount(double value) => value.isFinite
    ? value==value.roundToDouble()
      ? value.toInt().toString() : value.toStringAsFixed(1)
    : 'Unknown';

  @override
  Widget build(BuildContext context){
    final view=contextToken.inspect(
      catalog:catalog,currentOwnerId:currentOwnerId,
      forTitleId:titleId,workspace:workspace);
    if(view.status==NativeM52ContextStatus.differentTitle){
      return const SizedBox.shrink();
    }
    final colors=Theme.of(context).colorScheme;
    return Card(
      key:const Key('m52-context-panel'),
      margin:EdgeInsets.zero,
      color:colors.surfaceContainerLow,
      child:Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            Icon(view.ready?Icons.link_outlined:Icons.link_off_outlined,
              color:view.ready?colors.primary:colors.error,size:20),
            const SizedBox(width:7),
            Expanded(child:Text('Saved task · $method',
              key:const Key('m52-context-heading'),
              style:Theme.of(context).textTheme.titleSmall)),
          ]),
          const SizedBox(height:5),
          if(view.ready)
            Text('Task target: ${_amount(view.low)}–'
              '${_amount(view.high)} ${view.taskUnit}',
              key:const Key('m52-target')),
          Text(view.message,key:const Key('m52-context-message')),
          if(view.ready)...[
            const SizedBox(height:5),
            Text(view.draftSummary,
              key:const Key('m52-draft-continuity')),
            if(view.itemized!=null)
              Text('Existing season: ${view.itemized!.seasonName} '
                '· ${view.itemized!.unitNumbers.length} chosen units',
                key:const Key('m52-existing-season')),
            const Text('Context only: no automatic method conversion, '
              'timestamp reset, unit prefill, or task completion.',
              key:Key('m52-no-autofill')),
            if(showCompletionEvidence)...[
              const SizedBox(height:10),
              NativeM53CompletionEvidencePanel(
                taskContext:contextToken,catalog:catalog,titleId:titleId,
                currentOwnerId:currentOwnerId,workspace:workspace,
                variant:'saved'),
            ],
          ],
        ])),
    );
  }
}
