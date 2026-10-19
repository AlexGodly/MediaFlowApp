import 'package:flutter/material.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_m42_mixed_queue.dart';
import '../../services/native_m48_task_coordination.dart';

/// Local inspection only: no real task reroll, submission or traversal.
class NativeM48TaskCoordinationPanel extends StatefulWidget {
  const NativeM48TaskCoordinationPanel({
    super.key,required this.catalog,required this.categoryId,
    required this.onJump,this.savedCatalog,
  });
  final MediaFlowCatalog catalog;
  final MediaFlowCatalog? savedCatalog;
  final String categoryId;
  final void Function(String,String) onJump;

  @override
  State<NativeM48TaskCoordinationPanel> createState() =>
      _NativeM48TaskCoordinationPanelState();
}

class _NativeM48TaskCoordinationPanelState
    extends State<NativeM48TaskCoordinationPanel> {
  late NativeM48TaskCoordination engine;
  NativeM48TaskCoordination? saved;
  final exclusions=TextEditingController();
  bool simulate=false;

  void _reset() {
    engine=NativeM48TaskCoordination(widget.catalog);
    saved=widget.savedCatalog==null?null:
        NativeM48TaskCoordination(widget.savedCatalog!);
  }
  @override
  void initState(){super.initState();_reset();}
  @override
  void didUpdateWidget(covariant NativeM48TaskCoordinationPanel old) {
    super.didUpdateWidget(old);
    if(!identical(old.catalog,widget.catalog) ||
       !identical(old.savedCatalog,widget.savedCatalog)) {
      _reset();simulate=false;
    }
    if(old.categoryId!=widget.categoryId) {
      exclusions.clear();simulate=false;
    }
  }
  @override
  void dispose(){exclusions.dispose();super.dispose();}

  Set<String> get excluded => {
    for(final id in exclusions.text.split(RegExp(r'[\s,;]+')))
      if(id.trim().isNotEmpty) id.trim(),
  };
  String label(NativeM42QueueTitle? item) => item==null
      ?'No eligible queue candidate'
      :'${item.title.title} · recommendation #${item.recommendationIndex}'
       ' · outer slot #${item.outerPosition}'
       ' · ${item.fromCollection?"Collection":"Direct title"}';

  @override
  Widget build(BuildContext context) {
    NativeM48TaskPreview? current,original;
    NativeM48TraversalPreview? hypothetical;
    String? failure;
    try {
      current=engine.preview(widget.categoryId,excludedIds:excluded);
      if(saved!=null) {
        original=saved!.preview(widget.categoryId,excludedIds:excluded);
      }
      if(simulate&&current.first!=null) {
        hypothetical=engine.afterSuccessfulCollectionConsumption(
          widget.categoryId,current.first!,excludedIds:excluded);
      }
    } on StateError catch(e){failure=e.message;}
      on FormatException catch(e){failure=e.message;}
    final first=current?.first;
    final policy=switch(engine.policy){
      NativeM48PriorityPolicy.enabled =>
        'Prioritization enabled. Queue order can affect title selection.',
      NativeM48PriorityPolicy.disabled =>
        'Prioritization disabled. Website fallback picker is not modeled.',
      NativeM48PriorityPolicy.unknown =>
        'Priority setting unavailable; actual title selection is unknown.',
    };
    return ExpansionTile(
      key:const Key('m48-task-coordination'),
      tilePadding:EdgeInsets.zero,
      leading:const Icon(Icons.route_outlined),
      title:const Text('Task & recommendation coordination'),
      subtitle:const Text('Read-only preview · never an actual reroll'),
      children:[ConstrainedBox(
        constraints:const BoxConstraints(maxHeight:240),
        child:SingleChildScrollView(child:Padding(
          padding:const EdgeInsets.all(8),
          child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
            children:[
              Text(policy,key:const Key('m48-priority-state')),
              Text(engine.catalog.sessionActive &&
                   engine.catalog.currentTask!=null
                ?engine.activeCategoryId==widget.categoryId
                  ?'Active task category matches. Current task unchanged.'
                  :'Active task belongs to another category.'
                :'No active task. Category-only preview.',
                key:const Key('m48-current-task-context')),
              const SizedBox(height:6),
              TextField(
                key:const Key('m48-exclusion-input'),
                controller:exclusions,
                decoration:const InputDecoration(isDense:true,
                  border:OutlineInputBorder(),
                  labelText:'Hypothetical excluded title IDs',
                  helperText:'Comma or space separated; no history writes'),
                onChanged:(_)=>setState(()=>simulate=false)),
              if(failure!=null) Text(failure,
                key:const Key('m48-error'),
                style:TextStyle(color:Theme.of(context).colorScheme.error)),
              if(current!=null)...[
                Text('${current.eligibleCount} eligible · '
                  '${current.excludedCount} excluded · '
                  '${current.candidates.length} shown',
                  key:const Key('m48-queue-count')),
                Text(label(first),key:const Key('m48-first-candidate')),
                if(current.fallbackOrUnknown)
                  const Text('Actual website fallback/selection cannot '
                    'be inferred.',key:Key('m48-fallback')),
                for(var i=0;i<current.candidates.length;i++)
                  ListTile(
                    dense:true,
                    key:Key('m48-candidate-${current.candidates[i].title.id}'),
                    title:Text(current.candidates[i].title.title,
                      maxLines:1,overflow:TextOverflow.ellipsis),
                    subtitle:Text(label(current.candidates[i])),
                    trailing:IconButton(
                      key:Key('m48-jump-${current.candidates[i].title.id}'),
                      icon:const Icon(Icons.near_me_outlined),
                      tooltip:'Inspect original queue slot',
                      onPressed:(){
                        final c=current!.candidates[i];
                        widget.onJump(widget.categoryId,c.fromCollection
                          ?'c:${c.assignmentId}':'t:${c.title.id}');
                      }),
                  ),
                if(original!=null)...[
                  const Divider(),
                  Text('Saved: ${label(original.first)}',
                    key:const Key('m48-saved-first')),
                  Text('Local: ${label(first)}',
                    key:const Key('m48-local-first')),
                  Text(original.first?.title.id==first?.title.id
                    ?'First queue title unchanged.'
                    :'First queue title differs from saved state.',
                    key:const Key('m48-difference')),
                ],
                if(first!=null) SwitchListTile(
                  key:const Key('m48-simulate-switch'),
                  dense:true,value:simulate,
                  title:const Text('What if this candidate were logged?'),
                  subtitle:const Text('Assume successful consumption only.'),
                  onChanged:(value)=>setState(()=>simulate=value)),
                if(hypothetical!=null)...[
                  Text(hypothetical.wouldAdvanceCollection
                    ?'Would traverse Collection assignment '
                      '${hypothetical.assignmentId}'
                    :'Direct title: no Collection traversal',
                    key:const Key('m48-traversal-result')),
                  Text('Next queue first: ${label(hypothetical.after.first)}',
                    key:const Key('m48-next-candidate')),
                ],
              ],
              const Text('Preview only. No task generation, reroll, '
                'History/XP changes, cloud writes or traversal commit.'),
            ]),
        )),
      )],
    );
  }
}
