import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m44_personal_order_plan.dart';

/// Direct title order editing shares the M44 device-only, owner-pinned
/// checkpoint stack. This widget NEVER commits account, History or XP writes.
class NativeM45DirectTitlePlanner extends StatefulWidget {
  const NativeM45DirectTitlePlanner({
    super.key,required this.plan,required this.onPreview,
  });
  final NativeM44PersonalOrderPlan plan;
  final VoidCallback onPreview;

  @override
  State<NativeM45DirectTitlePlanner> createState() =>
      _NativeM45DirectTitlePlannerState();
}

class _NativeM45DirectTitlePlannerState
    extends State<NativeM45DirectTitlePlanner> {
  String categoryId='',search='';
  bool available=false;
  int page=0;
  final Set<String> selected={};
  String? error;
  static const pageSize=40;

  void _run(void Function() action) {
    try {
      action();
      setState(() {error=null;selected.clear();page=0;});
    } on StateError catch(e) {
      setState(()=>error=e.message);
    } on FormatException catch(e) {
      setState(()=>error=e.message);
    }
  }

  Future<bool> _confirm(String title,String description) async =>
    await showDialog<bool>(
      context:context,
      builder:(context)=>AlertDialog(
        title:Text(title),content:Text(description),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context,false),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('m45-confirm-bulk'),
            onPressed:()=>Navigator.pop(context,true),
            child:const Text('Confirm device-only change')),
        ],
      ),
    )??false;

  Future<void> _position(String id,int initial,int length) async {
    final controller=TextEditingController(text:'$initial');
    final result=await showDialog<int>(
      context:context,
      builder:(context)=>AlertDialog(
        title:const Text('Move ordered title'),
        content:TextField(
          key:const Key('m45-target-position'),
          controller:controller,
          keyboardType:TextInputType.number,
          decoration:InputDecoration(
            labelText:'Position 1–$length',
            border:const OutlineInputBorder()),
        ),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(context),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('m45-confirm-position'),
            onPressed:()=>Navigator.pop(context,int.tryParse(controller.text)),
            child:const Text('Move locally')),
        ],
      ),
    );
    controller.dispose();
    if(result!=null) {
      _run(()=>widget.plan.positionDirectTitle(id,result,
        categoryId:categoryId));
    }
  }

  void _selectAll(List<MediaFlowTitle> displayed) {
    setState(() {
      for(final title in displayed) {
        if(selected.length>=200) break;
        selected.add(title.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation:widget.plan,
    builder:(context,_) {
      final plan=widget.plan;
      if(!plan.canEdit) {
        return Column(children:[
          const Text('Direct Personal Order draft quarantined. '
            'Signed-in owner or authoritative account snapshot changed.',
            key:Key('m45-stale-warning')),
          FilledButton.icon(
            key:const Key('m45-discard-stale'),
            onPressed:plan.discard,
            icon:const Icon(Icons.delete_outline),
            label:const Text('Discard quarantined edits')),
        ]);
      }
      final data=plan.previewCatalog();
      final titleById=<String,MediaFlowTitle>{
        for(final t in data.library) t.id:t,
      };
      final categories=data.categories.where((c)=>c.id.isNotEmpty)
          .toList(growable:false);
      final categoryNames={
        for(final c in categories) c.id:c.name,
      };
      final effectiveCategory=categoryId.isEmpty ||
          categories.any((c)=>c.id==categoryId) ?categoryId:'';
      final ids=plan.directTitleIds;
      final orderedAll=<MediaFlowTitle>[];
      final categoryPositions=<String,int>{};
      var categoryIndex=0;
      for(final id in ids) {
        final title=titleById[id];
        if(title==null) { continue; }
        if(effectiveCategory.isNotEmpty &&
            title.categoryId!=effectiveCategory) {
          continue;
        }
        categoryPositions[id]=++categoryIndex;
        orderedAll.add(title);
      }
      final needle=search.trim().toLowerCase();
      final orderedFiltered=[
        for(final t in orderedAll)
          if(needle.isEmpty || t.searchText.contains(needle) ||
             t.id.toLowerCase().contains(needle)) t,
      ];
      final availableRows=available
        ?plan.browseDirectTitlePicker(
          categoryId:effectiveCategory,search:search,limit:60)
        :const <MediaFlowTitle>[];
      final candidates=available?availableRows:orderedFiltered;
      final pages=candidates.isEmpty?1:
        (candidates.length+pageSize-1)~/pageSize;
      final current=page.clamp(0,pages-1);
      final shown=candidates.skip(current*pageSize)
          .take(pageSize).toList(growable:false);
      // IDs not shown in this mode are still safely retained in a pending
      // selection; bulk validation happens again at command execution.
      return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        Text('Direct Personal Order · device-only planner',
          style:Theme.of(context).textTheme.titleMedium),
        const Text('LOCAL DRAFT · Library, Collection blocks, History, '
          'account data and XP are not modified.'),
        const SizedBox(height:8),
        Wrap(spacing:6,runSpacing:6,children:[
          OutlinedButton.icon(
            key:const Key('m45-undo'),
            onPressed:plan.canUndo?()=>_run(plan.undo):null,
            icon:const Icon(Icons.undo),label:const Text('Undo')),
          OutlinedButton.icon(
            key:const Key('m45-redo'),
            onPressed:plan.canRedo?()=>_run(plan.redo):null,
            icon:const Icon(Icons.redo),label:const Text('Redo')),
          OutlinedButton.icon(
            key:const Key('m45-discard'),
            onPressed:plan.hasChanges?()=>_run(plan.discard):null,
            icon:const Icon(Icons.delete_outline),
            label:const Text('Discard draft')),
          FilledButton.icon(
            key:const Key('m45-preview'),
            onPressed:widget.onPreview,
            icon:const Icon(Icons.visibility_outlined),
            label:const Text('View mixed queue preview')),
        ]),
        Text(plan.hasChanges
          ? '${plan.pendingOperations} staged operation(s), unsynchronized'
          : 'Saved Personal Order unchanged.',
          key:const Key('m45-draft-count')),
        Wrap(spacing:8,runSpacing:8,
          crossAxisAlignment:WrapCrossAlignment.center,children:[
          ChoiceChip(
            key:const Key('m45-ordered-tab'),
            label:const Text('Ordered titles'),
            selected:!available,
            onSelected:(_)=>setState(() {
              available=false;search='';page=0;selected.clear();
            })),
          ChoiceChip(
            key:const Key('m45-available-tab'),
            label:const Text('Add Library titles'),
            selected:available,
            onSelected:(_)=>setState(() {
              available=true;search='';page=0;selected.clear();
            })),
          DropdownButton<String>(
            key:const Key('m45-category-filter'),
            value:effectiveCategory,
            items:[
              const DropdownMenuItem(value:'',child:Text('Global order')),
              for(final c in categories)
                DropdownMenuItem(value:c.id,
                  child:Text(c.name,overflow:TextOverflow.ellipsis)),
            ],
            onChanged:(v)=>setState(() {
              categoryId=v??'';search='';page=0;selected.clear();
            })),
        ]),
        const SizedBox(height:8),
        TextField(
          key:const Key('m45-title-search'),
          decoration:const InputDecoration(
            labelText:'Search titles or Library IDs',
            border:OutlineInputBorder(),isDense:true,
            prefixIcon:Icon(Icons.search)),
          onChanged:(v)=>setState(() {
            search=v;page=0;selected.clear();
          })),
        if(error!=null)
          Text(error!,key:const Key('m45-error'),
            style:TextStyle(color:Theme.of(context).colorScheme.error)),
        const SizedBox(height:6),
        Text('${available ? "Available" : "Ordered"} · '
          '${available ? "${availableRows.length} shown (up to 60)" : "${orderedFiltered.length} matching"}'
          ' · ${selected.length} selected',
          key:const Key('m45-count')),
        Wrap(spacing:8,runSpacing:4,
          crossAxisAlignment:WrapCrossAlignment.center,children:[
          TextButton.icon(
            key:const Key('m45-select-visible'),
            onPressed:shown.isEmpty?null:()=>_selectAll(shown),
            icon:const Icon(Icons.select_all),
            label:const Text('Select visible')),
          TextButton.icon(
            key:const Key('m45-clear-selection'),
            onPressed:selected.isEmpty?null:
              ()=>setState(()=>selected.clear()),
            icon:const Icon(Icons.deselect),
            label:const Text('Clear selection')),
          FilledButton.icon(
            key:const Key('m45-apply-bulk'),
            onPressed:selected.isEmpty?null:() async {
              final ids=selected.toList(growable:false);
              if(available) {
                _run(()=>plan.addDirectTitles(ids));
              } else if(await _confirm(
                'Remove ${ids.length} direct order entries?',
                'Only the selected direct Personal Order references '
                'will be removed from this device draft. Titles remain '
                'in Library and Collection queues remain intact.')) {
                _run(()=>plan.removeDirectTitles(ids));
              }
            },
            icon:Icon(available?Icons.playlist_add:Icons.playlist_remove),
            label:Text(available?'Add selected locally':'Remove selected locally')),
        ]),
        const SizedBox(height:4),
        Expanded(child:shown.isEmpty
          ?Center(child:Text(available
            ? 'No matching available Library titles.'
            : 'No matching directly ordered titles.'))
          :ListView.builder(
            key:const Key('m45-direct-title-rows'),
            itemCount:shown.length,
            itemBuilder:(context,index) {
              final title=shown[index];
              final id=title.id;
              final position=categoryPositions[id];
              return Card(
                key:Key('m45-row-$id'),
                child:ListTile(
                  leading:Checkbox(
                    key:Key('m45-check-$id'),
                    value:selected.contains(id),
                    onChanged:(value)=>setState(() {
                      if(value==true && selected.length<200) {
                        selected.add(id);
                      } else if(value!=true) {
                        selected.remove(id);
                      }
                    })),
                  title:Text(title.title,
                    maxLines:2,overflow:TextOverflow.ellipsis),
                  subtitle:Text(available
                    ? '${categoryNames[title.categoryId]??title.categoryId} · ${title.status}'
                    : 'Position #${position??"?"} · '
                      '${categoryNames[title.categoryId]??title.categoryId}'),
                  trailing:available?null:
                    Row(mainAxisSize:MainAxisSize.min,children:[
                      IconButton(
                        key:Key('m45-up-$id'),
                        tooltip:'Move direct title earlier',
                        onPressed:position==null||position<=1?null:
                          ()=>_run(()=>plan.moveDirectTitle(id,-1,
                            categoryId:effectiveCategory)),
                        icon:const Icon(Icons.arrow_upward)),
                      IconButton(
                        key:Key('m45-down-$id'),
                        tooltip:'Move direct title later',
                        onPressed:position==null||
                            position>=orderedAll.length?null:
                          ()=>_run(()=>plan.moveDirectTitle(id,1,
                            categoryId:effectiveCategory)),
                        icon:const Icon(Icons.arrow_downward)),
                      IconButton(
                        key:Key('m45-position-$id'),
                        tooltip:'Set direct title position',
                        onPressed:position==null?null:
                          ()=>_position(id,position,orderedAll.length),
                        icon:const Icon(Icons.pin_outlined)),
                    ]),
                ),
              );
            },
          )),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          IconButton(
            key:const Key('m45-prev-page'),
            onPressed:current==0?null:
              ()=>setState(()=>page=current-1),
            icon:const Icon(Icons.chevron_left)),
          Text('Page ${current+1} of $pages'),
          IconButton(
            key:const Key('m45-next-page'),
            onPressed:current+1>=pages?null:
              ()=>setState(()=>page=current+1),
            icon:const Icon(Icons.chevron_right)),
        ]),
      ]);
    },
  );
}
