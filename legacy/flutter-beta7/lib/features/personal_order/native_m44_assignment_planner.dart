import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m42_mixed_queue.dart';
import '../../services/native_m44_personal_order_plan.dart';

/// Local-only source-anchored edit controls. Every operation is reversible
/// and cannot write mediaflow_states or update traversal/XP/task/history.
class NativeM44AssignmentPlanner extends StatefulWidget {
  const NativeM44AssignmentPlanner({
    super.key,required this.plan,required this.onPreview,
  });
  final NativeM44PersonalOrderPlan plan;
  final VoidCallback onPreview;

  @override
  State<NativeM44AssignmentPlanner> createState() =>
    _NativeM44AssignmentPlannerState();
}

class _NativeM44AssignmentPlannerState
    extends State<NativeM44AssignmentPlanner> {
  String categoryId='';
  String? error;

  void _run(void Function() action) {
    try {
      action();
      setState(()=>error=null);
    } on StateError catch(e) {
      setState(()=>error=e.message);
    } on FormatException catch(e) {
      setState(()=>error=e.message);
    }
  }

  Future<bool> _confirm(String title,String text) async =>
    await showDialog<bool>(context:context,builder:(context)=>
      AlertDialog(
        title:Text(title),content:Text(text),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context,false),
            child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(context,true),
            child:const Text('Confirm local change')),
        ],
      ))??false;

  Future<void> _add(String initialCategory) async {
    await showModalBottomSheet<void>(
      context:context,isScrollControlled:true,showDragHandle:true,
      builder:(context)=>_M44AddCollectionSheet(
        plan:widget.plan,categoryId:initialCategory),
    );
  }

  Future<void> _setPosition(String id,int max,int previous) async {
    final input=TextEditingController(text:'$previous');
    final value=await showDialog<int>(
      context:context,
      builder:(context)=>AlertDialog(
        title:const Text('Set Collection block position'),
        content:TextField(
          key:const Key('m44-position-input'),
          controller:input,keyboardType:TextInputType.number,
          decoration:InputDecoration(
            labelText:'Position from 1 to $max',
            border:const OutlineInputBorder()),
        ),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('m44-confirm-position'),
            onPressed:()=>Navigator.pop(context,int.tryParse(input.text)),
            child:const Text('Move locally')),
        ],
      ),
    );
    input.dispose();
    if(value!=null) _run(()=>widget.plan.setPosition(id,value));
  }

  Widget _ruleDropdown(String assignmentId,String key,String value,
      List<String> values,String label) =>
    SizedBox(width:190,child:DropdownButtonFormField<String>(
      key:Key('m44-$key-$assignmentId'),
      initialValue:value,isExpanded:true,
      decoration:InputDecoration(labelText:label,isDense:true,
        border:const OutlineInputBorder()),
      items:[
        for(final item in values)
          DropdownMenuItem(value:item,child:Text(item)),
      ],
      onChanged:(next) {
        if(next!=null) {
          _run(()=>widget.plan.setRules(assignmentId,
            categoryRule:key=='category'?next:null,
            completedRule:key=='completed'?next:null));
        }
      },
    ));

  Widget _assignmentRow(MediaFlowCollectionAssignment a,
      int position,int total,String collectionName) =>
    Card(key:Key('m44-assignment-${a.id}'),
      child:Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Wrap(spacing:8,runSpacing:4,
              crossAxisAlignment:WrapCrossAlignment.center,
              children:[
                const Icon(Icons.collections_bookmark_outlined),
                Text(collectionName,
                  style:Theme.of(context).textTheme.titleSmall),
                Text('Queue slot #$position of $total',
                  key:Key('m44-position-${a.id}')),
                if(a.id.startsWith('local_m44_'))
                  const Chip(label:Text('New local assignment')),
              ]),
            const SizedBox(height:8),
            Wrap(spacing:8,runSpacing:8,children:[
              _ruleDropdown(a.id,'category',a.categoryRule,
                const ['match','force'],'Category rule'),
              _ruleDropdown(a.id,'completed',a.completedRule,
                const ['skip','include'],'Completed titles'),
            ]),
            const SizedBox(height:8),
            Wrap(spacing:4,runSpacing:4,children:[
              IconButton(
                key:Key('m44-up-${a.id}'),
                tooltip:'Move Collection queue block earlier',
                onPressed:position<=1?null:
                  ()=>_run(()=>widget.plan.move(a.id,-1)),
                icon:const Icon(Icons.arrow_upward)),
              IconButton(
                key:Key('m44-down-${a.id}'),
                tooltip:'Move Collection queue block later',
                onPressed:position>=total?null:
                  ()=>_run(()=>widget.plan.move(a.id,1)),
                icon:const Icon(Icons.arrow_downward)),
              TextButton.icon(
                key:Key('m44-set-position-${a.id}'),
                onPressed:()=>_setPosition(a.id,total,position),
                icon:const Icon(Icons.pin_outlined),
                label:const Text('Position')),
              if(a.traversedTitleIds.isNotEmpty)
                TextButton.icon(
                  key:Key('m44-reset-${a.id}'),
                  onPressed:() async {
                    if(await _confirm('Reset traversal in local preview?',
                      'This clears traversal only in this device preview. '
                      'Production task history is unchanged.')) {
                      _run(()=>widget.plan.resetTraversal(a.id));
                    }
                  },
                  icon:const Icon(Icons.restart_alt_outlined),
                  label:Text('Reset preview progress (${a.traversedTitleIds.length})')),
              TextButton.icon(
                key:Key('m44-remove-${a.id}'),
                onPressed:() async {
                  if(await _confirm('Remove local Collection assignment?',
                    'This removes only the draft queue assignment, '
                    'not the Collection or its Library titles.')) {
                    _run(()=>widget.plan.remove(a.id));
                  }
                },
                icon:const Icon(Icons.link_off_outlined),
                label:const Text('Remove')),
            ]),
          ],
        ),
      ),
    );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation:widget.plan,
    builder:(context,_) {
      final plan=widget.plan;
      if(plan.stale||!plan.canEdit) {
        return Column(children:[
          const Text('Personal Order plan quarantined: the source '
            'snapshot or signed-in account changed.',
            key:Key('m44-stale-warning')),
          FilledButton.icon(
            key:const Key('m44-discard-stale'),
            onPressed:plan.discard,
            icon:const Icon(Icons.delete_outline),
            label:const Text('Discard quarantined local changes')),
        ]);
      }
      final data=plan.previewCatalog();
      final categories=data.categories.where((c)=>c.id.isNotEmpty)
          .toList(growable:false);
      if(categories.isEmpty) {
        return const Center(child:Text('No task categories for Collections.'));
      }
      final current=categories.any((c)=>c.id==categoryId)
        ?categoryId:categories.first.id;
      final reader=NativeM42MixedQueues(data);
      final tokens=reader.tokensForCategory(current);
      final positions={
        for(var i=0;i<tokens.length;i++) tokens[i]:i+1,
      };
      final names={
        for(final c in data.collections) c.id:c.title,
      };
      final rows=data.collectionAssignments.where((a)=>
        a.categoryId==current).toList(growable:false)
        ..sort((a,b)=>(positions['c:${a.id}']??999999)
            .compareTo(positions['c:${b.id}']??999999));
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,
        children:[
          Text('Device-only Personal Order assignment plan',
            style:Theme.of(context).textTheme.titleMedium),
          const Text('LOCAL PREVIEW ONLY · No cloud save, XP, '
            'Library/History edits or task advancement.'),
          Wrap(spacing:8,runSpacing:6,
            crossAxisAlignment:WrapCrossAlignment.center,children:[
            OutlinedButton.icon(
              key:const Key('m44-undo'),
              onPressed:plan.canUndo?plan.undo:null,
              icon:const Icon(Icons.undo),label:const Text('Undo')),
            OutlinedButton.icon(
              key:const Key('m44-redo'),
              onPressed:plan.canRedo?plan.redo:null,
              icon:const Icon(Icons.redo),label:const Text('Redo')),
            OutlinedButton.icon(
              key:const Key('m44-discard'),
              onPressed:plan.hasChanges?plan.discard:null,
              icon:const Icon(Icons.delete_outline),
              label:const Text('Discard plan')),
            FilledButton.icon(
              key:const Key('m44-preview'),
              onPressed:widget.onPreview,
              icon:const Icon(Icons.visibility_outlined),
              label:const Text('View local queue preview')),
          ]),
          Text(plan.hasChanges
            ? '${plan.pendingOperations} staged operation(s) · '
              'not synchronized'
            : 'No staged changes. Saved Personal Order is unchanged.',
            key:const Key('m44-draft-count')),
          const SizedBox(height:8),
          Wrap(spacing:8,runSpacing:8,
            crossAxisAlignment:WrapCrossAlignment.center,children:[
            DropdownButton<String>(
              key:const Key('m44-category'),
              value:current,
              items:[
                for(final c in categories)
                  DropdownMenuItem(value:c.id,
                    child:Text(c.name,overflow:TextOverflow.ellipsis)),
              ],
              onChanged:(next)=>setState(()=>categoryId=next??current),
            ),
            FilledButton.icon(
              key:const Key('m44-add-assignment'),
              onPressed:()=>_add(current),
              icon:const Icon(Icons.playlist_add),
              label:const Text('Add Collection to category')),
          ]),
          if(error!=null)
            Text(error!,key:const Key('m44-error'),
              style:TextStyle(color:Theme.of(context).colorScheme.error)),
          Text('${rows.length} Collection block(s) · '
            '${tokens.length} total mixed queue slots',
            key:const Key('m44-queue-count')),
          const SizedBox(height:6),
          Expanded(child:rows.isEmpty
            ? const Center(child:Text('No Collection assignments in this '
                'category. Add an existing Collection to plan one.'))
            : ListView.builder(
                key:const Key('m44-assignment-list'),
                itemCount:rows.length,
                itemBuilder:(context,index) {
                  final a=rows[index];
                  return _assignmentRow(a,positions['c:${a.id}']??0,
                    tokens.length,names[a.collectionId]??'Unavailable Collection');
                },
              )),
        ],
      );
    },
  );
}

class _M44AddCollectionSheet extends StatefulWidget {
  const _M44AddCollectionSheet({
    required this.plan,required this.categoryId,
  });
  final NativeM44PersonalOrderPlan plan;
  final String categoryId;

  @override
  State<_M44AddCollectionSheet> createState()=>
      _M44AddCollectionSheetState();
}

class _M44AddCollectionSheetState extends State<_M44AddCollectionSheet> {
  String search='';
  String? error;

  @override
  Widget build(BuildContext context) {
    final options=widget.plan.availableCollections(
      widget.categoryId,search:search);
    return SafeArea(child:FractionallySizedBox(heightFactor:.75,
      child:Padding(padding:const EdgeInsets.all(14),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
          children:[
            Text('Add Collection to Personal Order (local)',
              style:Theme.of(context).textTheme.titleMedium),
            const Text('Existing Collection reference only · '
              'no data duplication and no cloud write.'),
            const SizedBox(height:8),
            TextField(
              key:const Key('m44-picker-search'),
              decoration:const InputDecoration(
                labelText:'Search Collections',
                border:OutlineInputBorder(),
                prefixIcon:Icon(Icons.search)),
              onChanged:(value)=>setState(()=>search=value)),
            if(error!=null) Text(error!,
              style:TextStyle(color:Theme.of(context).colorScheme.error)),
            Expanded(child:options.isEmpty
              ?const Center(child:Text('No available matching Collections.'))
              :ListView.builder(
                itemCount:options.length,
                itemBuilder:(context,i) {
                  final collection=options[i];
                  return ListTile(
                    key:Key('m44-picker-${collection.id}'),
                    leading:const Icon(Icons.collections_bookmark),
                    title:Text(collection.title),
                    subtitle:Text('${collection.titleIds.length} titles'),
                    trailing:const Icon(Icons.add_circle_outline),
                    onTap:(){
                      try {
                        widget.plan.addCollection(
                          collection.id,widget.categoryId);
                        Navigator.pop(context);
                      } on StateError catch(e) {
                        setState(()=>error=e.message);
                      } on FormatException catch(e) {
                        setState(()=>error=e.message);
                      }
                    },
                  );
                },
              )),
          ],
        ),
      ),
    ));
  }
}
