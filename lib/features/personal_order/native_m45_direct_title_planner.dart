// ignore_for_file: prefer_interpolation_to_compose_strings
import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m44_personal_order_plan.dart';
import '../../services/native_m46_title_picker.dart';

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

enum _M46View { list, compact, cards, covers, coversTitles }

class _NativeM45DirectTitlePlannerState
    extends State<NativeM45DirectTitlePlanner> {
  String categoryId='',search='',statusFilter='',priorityFilter='';
  bool available=false;
  int page=0, pageSize=40;
  NativeM46Membership membership=NativeM46Membership.notAdded;
  NativeM46Sort pickerSort=NativeM46Sort.library;
  _M46View viewMode=_M46View.list;
  final Set<String> selected={};
  String? error;

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
        if(!available || !widget.plan.directTitleIds.contains(title.id)) {
          selected.add(title.id);
        }
      }
    });
  }


  Widget _cover(MediaFlowTitle title) {
    final url=Uri.tryParse(title.coverUrl);
    if(url!=null && (url.scheme=='https' || url.scheme=='http')) {
      return Image.network(title.coverUrl,fit:BoxFit.cover,
        errorBuilder:(context,error,stack)=>const Center(
          child:Icon(Icons.image_not_supported_outlined,size:32)));
    }
    return const Center(child:Icon(Icons.menu_book_outlined,size:36));
  }

  Widget _moveActions(String id,int? position,int total,String scope) =>
    Row(mainAxisSize:MainAxisSize.min,children:[
      IconButton(
        key:Key('m45-up-' + id),tooltip:'Move direct title earlier',
        visualDensity:VisualDensity.compact,
        onPressed:position==null || position<=1?null:
          ()=>_run(()=>widget.plan.moveDirectTitle(id,-1,categoryId:scope)),
        icon:const Icon(Icons.arrow_upward)),
      IconButton(
        key:Key('m45-down-' + id),tooltip:'Move direct title later',
        visualDensity:VisualDensity.compact,
        onPressed:position==null || position>=total?null:
          ()=>_run(()=>widget.plan.moveDirectTitle(id,1,categoryId:scope)),
        icon:const Icon(Icons.arrow_downward)),
      IconButton(
        key:Key('m45-position-' + id),tooltip:'Set direct title position',
        visualDensity:VisualDensity.compact,
        onPressed:position==null?null:()=>_position(id,position,total),
        icon:const Icon(Icons.pin_outlined)),
    ]);

  Widget _titleCard(MediaFlowTitle title,{
    required String categoryName,required int? position,
    required int orderedTotal,required String scope,
    required bool alreadyOrdered,required bool grid,
    required bool compact,required bool coversOnly,
  }) {
    final id=title.id;
    final blocked=available && alreadyOrdered;
    final check=Checkbox(
      key:Key('m45-check-' + id),value:selected.contains(id),
      onChanged:blocked?null:(value)=>setState(() {
        if(value==true && selected.length<200) {
          selected.add(id);
        } else if(value!=true) {
          selected.remove(id);
        }
      }));
    final subtitle=available
      ? categoryName + ' · ' + title.status +
          (alreadyOrdered?' · Already ordered':'')
      : 'Position #' + (position?.toString()??'?') + ' · ' + categoryName;
    final actions=available?const SizedBox.shrink():
      _moveActions(id,position,orderedTotal,scope);
    if(grid) {
      return Card(key:Key('m45-row-' + id),clipBehavior:Clip.antiAlias,
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Expanded(child:Stack(fit:StackFit.expand,children:[
            Semantics(label:title.title,child:_cover(title)),
            Positioned(top:2,left:2,child:Material(
              color:Theme.of(context).colorScheme.surface.withValues(alpha:0.88),
              borderRadius:BorderRadius.circular(32),child:check)),
            if(alreadyOrdered && available)
              Positioned(top:5,right:5,child:Icon(Icons.check_circle,
                color:Theme.of(context).colorScheme.primary)),
          ])),
          if(!coversOnly) Padding(
            padding:const EdgeInsets.symmetric(horizontal:6,vertical:3),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(title.title,maxLines:1,overflow:TextOverflow.ellipsis,
                style:Theme.of(context).textTheme.labelLarge),
              Text(subtitle,maxLines:1,overflow:TextOverflow.ellipsis,
                style:Theme.of(context).textTheme.bodySmall),
            ])),
          if(!available) FittedBox(
            fit:BoxFit.scaleDown,child:actions),
        ]));
    }
    return Card(key:Key('m45-row-' + id),
      child:LayoutBuilder(builder:(context,constraints) {
        final narrow=constraints.maxWidth<590;
        if(narrow) {
          return Padding(padding:const EdgeInsets.all(4),
            child:Column(children:[
              Row(children:[
                check,
                if(!compact) SizedBox(width:42,height:58,child:_cover(title)),
                const SizedBox(width:8),
                Expanded(child:Column(
                  crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Text(title.title,maxLines:compact?1:2,
                      overflow:TextOverflow.ellipsis),
                    Text(subtitle,maxLines:1,overflow:TextOverflow.ellipsis,
                      style:Theme.of(context).textTheme.bodySmall),
                  ])),
              ]),
              if(!available) Align(
                alignment:Alignment.centerRight,child:actions),
            ]));
        }
        return ListTile(dense:compact,
          leading:Row(mainAxisSize:MainAxisSize.min,children:[
            check,
            if(!compact) SizedBox(width:38,height:52,child:_cover(title)),
          ]),
          title:Text(title.title,maxLines:2,overflow:TextOverflow.ellipsis),
          subtitle:Text(subtitle,maxLines:1,
            overflow:TextOverflow.ellipsis),
          trailing:available?null:actions,
        );
      }));
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
          if((needle.isEmpty || t.searchText.contains(needle) ||
              t.id.toLowerCase().contains(needle)) &&
              (statusFilter.isEmpty || t.status==statusFilter) &&
              (priorityFilter.isEmpty || t.priority==priorityFilter)) t,
      ];
      final pickerPage=available?NativeM46TitlePicker(data,ids).browse(
        categoryId:effectiveCategory,search:search,
        status:statusFilter,priority:priorityFilter,
        membership:membership,sort:pickerSort,
        page:page,pageSize:pageSize):null;
      final pages=available?pickerPage!.pageCount:
        (orderedFiltered.isEmpty?1:
          (orderedFiltered.length+pageSize-1)~/pageSize);
      final current=available?pickerPage!.page:page.clamp(0,pages-1);
      final shown=available?pickerPage!.titles:
        orderedFiltered.skip(current*pageSize)
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
              available=true;membership=NativeM46Membership.notAdded;
              search='';page=0;selected.clear();
            })),
          SizedBox(width:210,child:DropdownButton<String>(
            isExpanded:true,
            key:const Key('m45-category-filter'),
            value:effectiveCategory,
            items:[
              const DropdownMenuItem(value:'',child:Text('Global order')),
              for(final c in categories)
                DropdownMenuItem(value:c.id,
                  child:Text(c.name,overflow:TextOverflow.ellipsis)),
            ],
            onChanged:(v)=>setState(() {
              categoryId=v??'';page=0;selected.clear();
            }))),
        ]),
        ExpansionTile(
          key:const Key('m46-tools-filters'),
          title:const Text('Tools & Filters'),
          initiallyExpanded:false,
          tilePadding:EdgeInsets.zero,
          children:[SizedBox(height:176,child:SingleChildScrollView(
            child:Wrap(spacing:12,runSpacing:6,children:[
            SizedBox(width:180,child:DropdownButtonFormField<String>(
              key:const Key('m46-status-filter'),initialValue:statusFilter,
              isExpanded:true,decoration:const InputDecoration(
                labelText:'Status',isDense:true),
              items:const [
                DropdownMenuItem(value:'',child:Text('All statuses')),
                DropdownMenuItem(value:'active',child:Text('In progress')),
                DropdownMenuItem(value:'paused',child:Text('On hold')),
                DropdownMenuItem(value:'completed',child:Text('Completed')),
                DropdownMenuItem(value:'planned',child:Text('Planned')),
                DropdownMenuItem(value:'dropped',child:Text('Dropped')),
              ],
              onChanged:(v)=>setState(() {
                statusFilter=v??'';page=0;selected.clear();
              }))),
            SizedBox(width:170,child:DropdownButtonFormField<String>(
              key:const Key('m46-priority-filter'),initialValue:priorityFilter,
              isExpanded:true,decoration:const InputDecoration(
                labelText:'Priority',isDense:true),
              items:const [
                DropdownMenuItem(value:'',child:Text('All priorities')),
                DropdownMenuItem(value:'high',child:Text('High')),
                DropdownMenuItem(value:'medium',child:Text('Medium')),
                DropdownMenuItem(value:'low',child:Text('Low')),
              ],
              onChanged:(v)=>setState(() {
                priorityFilter=v??'';page=0;selected.clear();
              }))),
            if(available) SizedBox(width:180,
              child:DropdownButtonFormField<NativeM46Membership>(
              key:const Key('m46-membership-filter'),initialValue:membership,
              isExpanded:true,decoration:const InputDecoration(
                labelText:'Library visibility',isDense:true),
              items:const [
                DropdownMenuItem(value:NativeM46Membership.notAdded,
                  child:Text('Not added')),
                DropdownMenuItem(value:NativeM46Membership.all,
                  child:Text('Show all')),
                DropdownMenuItem(value:NativeM46Membership.alreadyAdded,
                  child:Text('Already added')),
              ],
              onChanged:(v)=>setState(() {
                membership=v??NativeM46Membership.notAdded;
                page=0;selected.clear();
              }))),
            if(available) SizedBox(width:175,
              child:DropdownButtonFormField<NativeM46Sort>(
              key:const Key('m46-sort-filter'),initialValue:pickerSort,
              isExpanded:true,decoration:const InputDecoration(
                labelText:'Display sort',isDense:true),
              items:const [
                DropdownMenuItem(value:NativeM46Sort.library,
                  child:Text('Library order')),
                DropdownMenuItem(value:NativeM46Sort.alphabetical,
                  child:Text('Title A–Z')),
                DropdownMenuItem(value:NativeM46Sort.priority,
                  child:Text('Priority')),
                DropdownMenuItem(value:NativeM46Sort.progress,
                  child:Text('Progress')),
              ],
              onChanged:(v)=>setState(() {
                pickerSort=v??NativeM46Sort.library;
                page=0;selected.clear();
              }))),
            SizedBox(width:115,child:DropdownButtonFormField<int>(
              key:const Key('m46-page-size'),initialValue:pageSize,
              decoration:const InputDecoration(labelText:'Per page',
                isDense:true),
              items:const [
                DropdownMenuItem(value:20,child:Text('20')),
                DropdownMenuItem(value:40,child:Text('40')),
                DropdownMenuItem(value:60,child:Text('60')),
                DropdownMenuItem(value:100,child:Text('100')),
              ],
              onChanged:(v)=>setState(() {
                pageSize=v??40;page=0;
              }))),
            SizedBox(width:165,child:DropdownButtonFormField<_M46View>(
              key:const Key('m46-view-mode'),initialValue:viewMode,
              isExpanded:true,decoration:const InputDecoration(
                labelText:'Display mode',isDense:true),
              items:const [
                DropdownMenuItem(value:_M46View.list,child:Text('List')),
                DropdownMenuItem(value:_M46View.compact,child:Text('Compact')),
                DropdownMenuItem(value:_M46View.cards,child:Text('Cards')),
                DropdownMenuItem(value:_M46View.covers,child:Text('Covers')),
                DropdownMenuItem(value:_M46View.coversTitles,
                  child:Text('Covers + Titles')),
              ],
              onChanged:(v)=>setState(()=>viewMode=v??_M46View.list))),
          ])))],
        ),
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
          '${available ? "${pickerPage!.total} matching Library titles" : "${orderedFiltered.length} matching"}'
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
          ? Center(child:Text(available
              ? 'No matching Library titles for these filters.'
              : 'No matching directly ordered titles.'))
          : LayoutBuilder(builder:(context,constraints) {
            final gridMode=viewMode==_M46View.cards ||
                viewMode==_M46View.covers ||
                viewMode==_M46View.coversTitles;
            final narrow=constraints.maxWidth<390;
            final maxExtent=narrow?170.0:215.0;
            Widget render(int index) {
              final title=shown[index];
              return _titleCard(title,
                categoryName:categoryNames[title.categoryId]??
                    title.categoryId,
                position:categoryPositions[title.id],
                orderedTotal:orderedAll.length,scope:effectiveCategory,
                alreadyOrdered:ids.contains(title.id),
                grid:gridMode,compact:viewMode==_M46View.compact,
                coversOnly:viewMode==_M46View.covers);
            }
            if(gridMode) {
              return GridView.builder(
                key:const Key('m45-direct-title-rows'),
                gridDelegate:SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent:maxExtent,
                  childAspectRatio:viewMode==_M46View.covers?0.78:0.60,
                  crossAxisSpacing:4,mainAxisSpacing:4),
                itemCount:shown.length,
                itemBuilder:(context,index)=>render(index));
            }
            return ListView.builder(
              key:const Key('m45-direct-title-rows'),
              itemCount:shown.length,
              itemBuilder:(context,index)=>render(index));
          })),
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
