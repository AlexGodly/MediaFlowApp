import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m42_mixed_queue.dart';
import '../../services/native_m44_personal_order_plan.dart';
import '../../services/native_m48_task_coordination.dart';
import '../../services/native_m49_dashboard_task_audit.dart';

/// Opt-in evidence view. Large Library/queue projections are created only
/// after expansion, and never cause task, History or Supabase writes.
class NativeM49DashboardEvidencePanel extends StatefulWidget {
  const NativeM49DashboardEvidencePanel({
    super.key,required this.catalog,required this.openPersonalOrder,
    this.plan,
  });
  final MediaFlowCatalog catalog;
  final NativeM44PersonalOrderPlan? plan;
  final VoidCallback? openPersonalOrder;

  @override
  State<NativeM49DashboardEvidencePanel> createState() =>
      _NativeM49DashboardEvidencePanelState();
}

class _NativeM49DashboardEvidencePanelState
    extends State<NativeM49DashboardEvidencePanel> {
  final exclusions=TextEditingController();
  bool expanded=false;
  String categoryId='';
  NativeM49DashboardTaskAudit? _auditCache;
  MediaFlowCatalog? _auditCatalog;

  @override
  void initState(){
    super.initState();
    widget.plan?.addListener(_changed);
  }
  void _changed(){if(mounted&&expanded)setState((){});}
  @override
  void didUpdateWidget(covariant NativeM49DashboardEvidencePanel old){
    super.didUpdateWidget(old);
    if(old.plan!=widget.plan){
      old.plan?.removeListener(_changed);
      widget.plan?.addListener(_changed);
    }
    if(!identical(old.catalog,widget.catalog)){
      _auditCache=null;_auditCatalog=null;
      categoryId='';exclusions.clear();
    }
  }
  @override
  void dispose(){
    widget.plan?.removeListener(_changed);
    exclusions.dispose();
    super.dispose();
  }

  NativeM49DashboardTaskAudit _audit(){
    if(_auditCache==null||!identical(_auditCatalog,widget.catalog)){
      _auditCatalog=widget.catalog;
      _auditCache=NativeM49DashboardTaskAudit(widget.catalog);
    }
    return _auditCache!;
  }

  String _first(NativeM48TaskPreview? preview){
    final item=preview?.first;
    if(item==null)return 'No eligible queue candidate';
    return '${item.title.title} · recommendation #'
      '${item.recommendationIndex} · slot #${item.outerPosition}'
      ' · ${item.fromCollection?"Collection":"Direct title"}';
  }

  Widget _details(BuildContext context){
    final choices=<String>{
      for(final c in widget.catalog.categories) if(c.id.isNotEmpty)c.id,
      ...widget.catalog.categoryQueues.keys.where((id)=>id.isNotEmpty),
      if(widget.catalog.currentTask?.categoryId.isNotEmpty==true)
        widget.catalog.currentTask!.categoryId,
    }.toList();
    if(choices.isEmpty){
      return const Padding(padding:EdgeInsets.all(10),
        child:Text('No category available for queue evidence.'));
    }
    final taskCategory=widget.catalog.currentTask?.categoryId??'';
    final selected=choices.contains(categoryId)?categoryId:
        choices.contains(taskCategory)?taskCategory:choices.first;
    final excluded=<String>{
      for(final id in exclusions.text.split(RegExp(r'[\s,;]+')))
        if(id.trim().isNotEmpty)id.trim(),
    };
    NativeM49DashboardTaskEvidence? evidence,draft;
    String? error;
    try {
      evidence=_audit().inspect(categoryId:selected,
        excludedTitleIds:excluded);
      final plan=widget.plan;
      if(plan!=null && plan.canEdit && plan.hasChanges &&
          identical(plan.source,widget.catalog)){
        draft=NativeM49DashboardTaskAudit(plan.previewCatalog())
          .inspect(categoryId:selected,excludedTitleIds:excluded);
      }
    } on StateError catch(e){error=e.message;}
      on FormatException catch(e){error=e.message;}
    return Padding(padding:const EdgeInsets.all(12),
      child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Wrap(spacing:8,runSpacing:6,
          crossAxisAlignment:WrapCrossAlignment.center,children:[
            DropdownButton<String>(
              key:const Key('m49-category'),
              value:selected,
              items:[for(final id in choices) DropdownMenuItem(
                value:id,child:Text(widget.catalog.categoryById[id]?.name??id,
                  overflow:TextOverflow.ellipsis))],
              onChanged:(value)=>setState((){
                categoryId=value??selected;exclusions.clear();
              })),
            if(widget.openPersonalOrder!=null)TextButton.icon(
              key:const Key('m49-open-order'),
              onPressed:widget.openPersonalOrder,
              icon:const Icon(Icons.format_list_numbered),
              label:const Text('Open Personal Order')),
        ]),
        const Text('READ-ONLY · No task generation, real rerolls, '
          'logging, XP or cloud state changes.',
          key:Key('m49-readonly-warning')),
        const SizedBox(height:6),
        TextField(
          key:const Key('m49-exclusions'),
          controller:exclusions,
          decoration:const InputDecoration(
            isDense:true,border:OutlineInputBorder(),
            labelText:'Hypothetical excluded title IDs',
            helperText:'Comma or space separated · no history writes'),
          onChanged:(_)=>setState((){})),
        if(error!=null)Text(error,key:const Key('m49-error')),
        if(evidence!=null)...[
          const SizedBox(height:5),
          Text('Evidence status: ${evidence.status.name}',
            key:const Key('m49-status')),
          Text(evidence.details,key:const Key('m49-explanation')),
          if(evidence.currentMatch!=null)
            Text('Saved task match: '
              '${evidence.currentMatch!.title.title} · queue rank #'
              '${evidence.currentMatch!.recommendationIndex} · slot #'
              '${evidence.currentMatch!.outerPosition}',
              key:const Key('m49-task-rank')),
          Text('Saved queue first: ${_first(evidence.queuePreview)}',
            key:const Key('m49-saved-first')),
          Text('Personal Order priority: ${evidence.priority.name}',
            key:const Key('m49-priority')),
          if(evidence.queuePreview?.fallbackOrUnknown==true)
            const Text('The website fallback cannot be predicted from '
              'this queue.',key:Key('m49-fallback')),
          for(final item in evidence.queuePreview?.candidates ??
              const <NativeM42QueueTitle>[])
            ListTile(
              dense:true,key:Key('m49-candidate-${item.title.id}'),
              leading:const Icon(Icons.queue_play_next,size:20),
              title:Text(item.title.title,maxLines:1,
                overflow:TextOverflow.ellipsis),
              subtitle:Text('Queue rank #${item.recommendationIndex} · '
                'outer slot #${item.outerPosition}'
                ' · ${item.fromCollection?"Collection":"Direct"}')),
          if(draft!=null)...[
            const Divider(),
            Text('Local draft first: ${_first(draft.queuePreview)}',
              key:const Key('m49-draft-first')),
            Text(draft.queuePreview?.first?.title.id==
                evidence.queuePreview?.first?.title.id
              ?'First queue candidate unchanged.'
              :'First queue candidate differs from saved state.',
              key:const Key('m49-draft-difference')),
          ],
        ],
      ]));
  }

  @override
  Widget build(BuildContext context)=>Card(
    child:ExpansionTile(
      key:const Key('m49-dashboard-evidence'),
      leading:const Icon(Icons.fact_check_outlined),
      title:const Text('Task & Personal Order evidence'),
      subtitle:const Text('Inspect saved recommendation provenance'),
      onExpansionChanged:(value)=>setState(()=>expanded=value),
      children:expanded?[_details(context)]:const [],
    ),
  );
}
