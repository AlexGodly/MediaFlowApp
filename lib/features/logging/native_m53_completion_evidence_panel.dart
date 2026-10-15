// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_editing_workspace.dart';
import '../../services/native_logging_parity_preview.dart';
import '../../services/native_itemized_parity.dart';
import '../../services/native_m52_task_draft_context.dart';
import '../../services/native_m53_task_completion_evidence.dart';

/// Read-only evidence only: there is deliberately no commit or award action.
class NativeM53CompletionEvidencePanel extends StatelessWidget {
  const NativeM53CompletionEvidencePanel({
    super.key, required this.taskContext, required this.catalog,
    required this.titleId, required this.currentOwnerId,
    this.workspace, this.standardPreview, this.itemizedPreview,
    this.variant='saved',
  });
  final NativeM52TaskDraftContext taskContext;
  final MediaFlowCatalog catalog;
  final String titleId, currentOwnerId, variant;
  final NativeEditingWorkspace? workspace;
  final NativeLoggingPreview? standardPreview;
  final NativeItemizedPreview? itemizedPreview;

  @override
  Widget build(BuildContext context){
    final contextView=taskContext.inspect(
      catalog:catalog, currentOwnerId:currentOwnerId,
      forTitleId:titleId, workspace:workspace);
    if(contextView.status==NativeM52ContextStatus.differentTitle){
      return const SizedBox.shrink();
    }
    final e=NativeM53TaskCompletionEvidence.evaluate(
      context:contextView, catalog:catalog, titleId:titleId,
      standardPreview:standardPreview,itemizedPreview:itemizedPreview);
    final theme=Theme.of(context);
    return Card(
      key:Key('m53-evidence-$variant'),margin:EdgeInsets.zero,
      child:Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Row(children:[
            const Icon(Icons.fact_check_outlined,size:20),
            const SizedBox(width:8),
            Expanded(child:Text('Task evidence · $variant',
              style:theme.textTheme.titleSmall)),
          ]),
          Text(e.bandLabel,key:Key('m53-status-$variant'),
            style:theme.textTheme.labelLarge),
          if(e.comparable)...[
            Text('Draft quantity: '+e.amount.toStringAsFixed(1)+
              ' · saved range: '+e.low.toStringAsFixed(1)+
              '–'+e.high.toStringAsFixed(1)+' '+e.unit,
              key:Key('m53-quantity-$variant')),
            const SizedBox(height:5),
            Semantics(label:'Indicative saved target upper bound percentage',
              child:LinearProgressIndicator(
                key:Key('m53-band-progress-$variant'),
                value:e.bandProgress,minHeight:6,
                borderRadius:BorderRadius.circular(6))),
          ],
          Text('Evidence source: '+e.source.name,
            key:Key('m53-source-$variant'),
            style:theme.textTheme.bodySmall),
          if(e.source!=NativeM53EvidenceSource.none)
            Text(e.repeat
              ?'Repeat logging may count as consumption, but cannot '
                'advance confirmed Library progress.'
              :'Library completion is a separate hypothetical outcome.',
              key:Key('m53-repeat-$variant'),
              style:theme.textTheme.bodySmall),
          if(e.projectedLibraryProgress!=null)
            Text('Estimated Library progress: '+
              e.projectedLibraryProgress!.toStringAsFixed(1),
              key:Key('m53-library-$variant')),
          const SizedBox(height:7),
          Text(e.explanation,key:Key('m53-explanation-$variant'),
            style:theme.textTheme.bodySmall),
          const SizedBox(height:5),
          Text('Confirmed task completion: unavailable · '
            'XP: unavailable · Collection traversal: not applied',
            key:Key('m53-no-commit-$variant')),
        ])),
    );
  }
}
