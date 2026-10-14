import 'package:flutter/material.dart';
import '../../data/mediaflow_models.dart';
import '../../services/native_m40_collection_plan.dart';
import '../../services/native_m41_collection_browser.dart';

/// Native v274 mini-Library browsing. Saved ordering stays authoritative;
/// display-only filtering/sorting never modifies the Collection or queue.
class NativeM41CollectionBrowser extends StatefulWidget {
  const NativeM41CollectionBrowser({
    super.key,required this.catalog,required this.collection,
    required this.plan,required this.onMove,required this.onRemove,
  });
  final MediaFlowCatalog catalog;
  final MediaFlowCollection collection;
  final NativeM40CollectionPlan? plan;
  final void Function(String id,int position) onMove;
  final void Function(String id) onRemove;

  @override
  State<NativeM41CollectionBrowser> createState() =>
      _NativeM41CollectionBrowserState();
}

class _NativeM41CollectionBrowserState extends State<NativeM41CollectionBrowser> {
  String search = '', category = '', status = '', priority = '', cover = 'all';
  NativeM41Sort sort = NativeM41Sort.saved;
  NativeM41View view = NativeM41View.list;
  double? minimumRating;
  int page=0,pageSize=25;
  final Set<String> selected = {};
  String? error;

  @override
  void didUpdateWidget(covariant NativeM41CollectionBrowser old) {
    super.didUpdateWidget(old);
    if (old.collection.id != widget.collection.id) {
      search='';category='';status='';priority='';cover='all';
      sort=NativeM41Sort.saved;view=NativeM41View.list;
      minimumRating=null;page=0;selected.clear();error=null;
    }
    // Do not silently carry a selected ID after external membership changes.
    selected.removeWhere((id)=>!widget.collection.titleIds.contains(id));
  }

  bool get canChange => widget.plan != null && !widget.plan!.stale;
  bool get savedUnfiltered => search.isEmpty && category.isEmpty &&
    status.isEmpty && priority.isEmpty && minimumRating == null &&
    cover == 'all' && sort == NativeM41Sort.saved;

  void _filter(VoidCallback update) => setState(() {
    update();page=0;selected.clear();
  });

  Future<void> _removeSelected() async {
    if (!canChange || selected.isEmpty) return;
    final ids=selected.toList(growable:false);
    if (ids.length > 200) {
      setState(()=>error='Select no more than 200 members at a time.');
      return;
    }
    final impact=inspectCollectionOrderImpact(widget.catalog,widget.collection);
    final confirmed=await showDialog<bool>(
      context:context,
      builder:(dialog)=>AlertDialog(
        title:Text('Remove ${ids.length} titles from Collection?'),
        content:Text('LOCAL PREVIEW ONLY. Library titles, History, XP and '
          'Personal Order will not be edited. ${impact.assignments.length} '
          'Personal Order Collection assignment(s) could be affected by '
          'future synchronized changes.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Cancel')),
          FilledButton(
            key:const Key('m41-confirm-bulk-remove'),
            onPressed:()=>Navigator.pop(dialog,true),
            child:const Text('Stage local removal')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      widget.plan!.removeTitles(widget.collection.id,ids);
      setState(() { selected.clear();error=null; });
    } on StateError catch(e) {
      setState(()=>error=e.message);
    } on FormatException catch(e) {
      setState(()=>error=e.message);
    }
  }

  Widget _dropdown<T>(T value,List<DropdownMenuItem<T>> items,
      ValueChanged<T> change,{Key? key}) =>
    DropdownButton<T>(
      key:key,value:value,items:items,
      onChanged:(next) { if (next != null) _filter(()=>change(next)); });

  @override
  Widget build(BuildContext context) {
    final byId={for (final t in widget.catalog.library)t.id:t};
    final members=browseCollection(widget.collection,byId,
      NativeM41BrowseOptions(
        search:search,categoryId:category,status:status,priority:priority,
        minRating:minimumRating,cover:cover,sort:sort,page:page,
        pageSize:pageSize));
    final impact=inspectCollectionOrderImpact(widget.catalog,widget.collection);
    final visible=members.items.map((e)=>e.id).toSet();
    final allVisibleSelected=visible.isNotEmpty && selected.containsAll(visible);
    final cs=Theme.of(context).colorScheme;
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      if (widget.collection.description.isNotEmpty)
        Text(widget.collection.description,maxLines:2,
          overflow:TextOverflow.ellipsis),
      Padding(
        padding:const EdgeInsets.symmetric(vertical:6),
        child: Text('${widget.collection.titleIds.length} saved references · '
          '${members.total} matches · page ${members.page+1}/${members.pages}',
          key:const Key('m41-member-count')),
      ),
      ExpansionTile(
        key:const Key('m41-order-impact'),
        tilePadding:EdgeInsets.zero,
        leading:const Icon(Icons.account_tree_outlined),
        title:Text('Personal Order references · '
          '${impact.assignments.length} Collection assignment(s)'),
        subtitle:Text('${impact.directMembers} directly ordered member(s) · '
          '${impact.traversedMembers} tracked queue member(s)'),
        children:[
          if (!impact.requiresQueueReview)
            const ListTile(title:Text('No known Personal Order references.')),
          for (final assignment in impact.assignments)
            ListTile(
              dense:true,
              title:Text('Category: ${assignment.categoryId}'),
              subtitle:Text('Rule: ${assignment.categoryRule} · '
                'Completed: ${assignment.completedRule} · '
                'Traversal: ${assignment.traversedTitleIds.length} title(s)'),
            ),
          const Padding(
            padding:EdgeInsets.all(8),
            child:Text('Read-only diagnostics. Collection queue positions '
              'and category-specific eligibility need full v410 execution. '
              'No Personal Order assignments, traversal state or ranks are '
              'updated by local Collection edits.'),
          ),
        ],
      ),
      TextField(
        key:const Key('m41-search'),
        decoration:const InputDecoration(
          labelText:'Search titles in Collection',isDense:true,
          prefixIcon:Icon(Icons.search),border:OutlineInputBorder()),
        onChanged:(value)=>_filter(()=>search=value),
      ),
      const SizedBox(height:5),
      SingleChildScrollView(
        scrollDirection:Axis.horizontal,
        child:Row(children:[
          _dropdown<String>(category,[
            const DropdownMenuItem(value:'',child:Text('All categories')),
            for(final c in widget.catalog.categories)
              DropdownMenuItem(value:c.id,child:Text(c.name)),
          ],(v)=>category=v,key:const Key('m41-category')),
          const SizedBox(width:10),
          _dropdown<String>(status,[
            const DropdownMenuItem(value:'',child:Text('All statuses')),
            for(final s in ['planned','active','paused','dropped','completed'])
              DropdownMenuItem(value:s,child:Text(s)),
          ],(v)=>status=v,key:const Key('m41-status')),
          const SizedBox(width:10),
          _dropdown<String>(priority,[
            const DropdownMenuItem(value:'',child:Text('All priorities')),
            for(final p in ['low','medium','high'])
              DropdownMenuItem(value:p,child:Text(p)),
          ],(v)=>priority=v,key:const Key('m41-priority')),
          const SizedBox(width:10),
          DropdownButton<double?>(
            key:const Key('m41-rating'),
            value:minimumRating,
            items:[
              const DropdownMenuItem<double?>(value:null,
                child:Text('All ratings')),
              for(final n in [5.0,6.0,7.0,8.0,9.0])
                DropdownMenuItem<double?>(value:n,
                  child:Text('${n.toInt()}+')),
            ],
            onChanged:(v)=>_filter(()=>minimumRating=v),
          ),
          const SizedBox(width:10),
          _dropdown<String>(cover,[
            const DropdownMenuItem(value:'all',child:Text('All covers')),
            const DropdownMenuItem(value:'with',child:Text('With cover')),
            const DropdownMenuItem(value:'without',child:Text('Missing cover')),
          ],(v)=>cover=v,key:const Key('m41-covers')),
        ]),
      ),
      Wrap(spacing:8,runSpacing:4,crossAxisAlignment:WrapCrossAlignment.center,
        children:[
          _dropdown<NativeM41Sort>(sort,[
            for(final s in NativeM41Sort.values)
              DropdownMenuItem(value:s,
                child:Text(s==NativeM41Sort.saved?'Saved order':
                  s.name)),
          ],(v)=>sort=v,key:const Key('m41-sort')),
          _dropdown<NativeM41View>(view,[
            for(final v in NativeM41View.values)
              DropdownMenuItem(value:v,child:Text(
                switch(v){
                  NativeM41View.list=>'List',
                  NativeM41View.compact=>'Compact',
                  NativeM41View.cards=>'Cards',
                  NativeM41View.covers=>'Covers',
                  NativeM41View.coversTitles=>'Covers + Titles',
                })),
          ],(v)=>view=v,key:const Key('m41-view')),
          _dropdown<int>(pageSize,[
            for (final n in [25,50,100,200])
              DropdownMenuItem(value:n,child:Text('$n/page')),
          ],(v)=>pageSize=v,key:const Key('m41-per-page')),
          if (canChange)
            TextButton.icon(
              key:const Key('m41-select-visible'),
              onPressed:visible.isEmpty ? null :
                ()=>setState(() {
                  if (allVisibleSelected) { selected.removeAll(visible); }
                  else { selected.addAll(visible); }
                }),
              icon:Icon(allVisibleSelected ? Icons.deselect :
                Icons.select_all),
              label:Text(allVisibleSelected ? 'Deselect visible' :
                'Select visible')),
          if (canChange)
            FilledButton.tonalIcon(
              key:const Key('m41-remove-selected'),
              onPressed:selected.isEmpty ? null : _removeSelected,
              icon:const Icon(Icons.remove_circle_outline),
              label:Text('Remove selected (${selected.length})')),
        ]),
      if (error != null) Text(error!,
        style:TextStyle(color:cs.error),key:const Key('m41-bulk-error')),
      if (selected.isNotEmpty)
        Text('Only selected member IDs will be removed locally. '
          'No Library title will be deleted.',
          style:Theme.of(context).textTheme.bodySmall),
      Expanded(
        child:members.items.isEmpty
          ? const Center(child:Text('No Collection titles match these filters.'))
          : (view == NativeM41View.list || view == NativeM41View.compact)
          ? ListView.builder(
              itemCount:members.items.length,
              itemBuilder:(context,i)=>_row(members.items[i],
                compact:view == NativeM41View.compact))
          : LayoutBuilder(builder:(context,constraints) {
              final width=constraints.maxWidth;
              final columns=width<380?2:width<680?3:width<1000?4:5;
              return GridView.builder(
                itemCount:members.items.length,
                gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:columns,crossAxisSpacing:8,
                  mainAxisSpacing:8,
                  childAspectRatio:view==NativeM41View.covers?.80:
                    view==NativeM41View.coversTitles?.63:.92),
                itemBuilder:(context,i)=>_card(members.items[i]));
            }),
      ),
      Row(mainAxisAlignment:MainAxisAlignment.center,children:[
        IconButton(
          key:const Key('m41-page-prev'),tooltip:'Previous Collection page',
          onPressed:members.page==0?null:()=>setState(() {
            page=members.page-1;selected.clear();
          }),
          icon:const Icon(Icons.chevron_left)),
        Text('Page ${members.page+1} / ${members.pages}'),
        IconButton(
          key:const Key('m41-page-next'),tooltip:'Next Collection page',
          onPressed:members.page>=members.pages-1?null:()=>setState(() {
            page=members.page+1;selected.clear();
          }),
          icon:const Icon(Icons.chevron_right)),
      ]),
    ]);
  }

  Widget _cover(MediaFlowTitle title,{double width=44,double height=58}) =>
    title.coverUrl.isEmpty ? SizedBox(width:width,height:height,
      child:const Icon(Icons.book_outlined))
    : Image.network(title.coverUrl,width:width,height:height,
      fit:BoxFit.cover,errorBuilder:(_,_,_)=>SizedBox(
        width:width,height:height,child:const Icon(Icons.book_outlined)));

  Widget _row(MediaFlowTitle item,{required bool compact}) {
    final index=widget.collection.titleIds.indexOf(item.id);
    final editable=canChange && savedUnfiltered;
    return Card(
      child:ListTile(
        dense:compact,
        leading:_cover(item,width:compact?31:42,height:compact?42:58),
        title:Text(item.title,maxLines:compact?1:2,
          overflow:TextOverflow.ellipsis),
        subtitle:Text('${item.status} · ${item.priority} · '
          '${item.progress.toStringAsFixed(0)}/'
          '${item.total?.toStringAsFixed(0) ?? "?"}'),
        trailing:widget.plan == null ? null :
          Row(mainAxisSize:MainAxisSize.min,children:[
            Checkbox(
              key:Key('m41-check-${item.id}'),
              value:selected.contains(item.id),
              onChanged:canChange ? (v)=>setState(() {
                if (v==true) { selected.add(item.id); }
                else { selected.remove(item.id); }
              }) : null),
            IconButton(
              key:Key('m40-up-${item.id}'),
              tooltip:'Move member earlier',
              onPressed:editable && index>0 ?
                ()=>widget.onMove(item.id,index-1):null,
              icon:const Icon(Icons.arrow_upward,size:19)),
            IconButton(
              key:Key('m40-down-${item.id}'),
              tooltip:'Move member later',
              onPressed:editable && index>=0 &&
                index<widget.collection.titleIds.length-1 ?
                ()=>widget.onMove(item.id,index+1):null,
              icon:const Icon(Icons.arrow_downward,size:19)),
            IconButton(
              key:Key('m40-remove-${item.id}'),
              tooltip:'Remove member locally',
              onPressed:canChange ? ()=>widget.onRemove(item.id):null,
              icon:const Icon(Icons.remove_circle_outline,size:19)),
          ]),
      ),
    );
  }

  Widget _card(MediaFlowTitle item) {
    final withText=view!=NativeM41View.covers;
    final coverHeight=view==NativeM41View.cards?72:122;
    return Card(clipBehavior:Clip.antiAlias,
      child:Padding(padding:const EdgeInsets.all(5),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Expanded(child:Center(child:_cover(item,
            width:double.infinity,height:coverHeight.toDouble()))),
          if (withText)
            Text(item.title,maxLines:view==NativeM41View.coversTitles?2:1,
              overflow:TextOverflow.ellipsis,
              style:Theme.of(context).textTheme.labelMedium),
          if (view==NativeM41View.cards)
            Text('${item.status} · ${item.priority}',
              maxLines:1,overflow:TextOverflow.ellipsis,
              style:Theme.of(context).textTheme.labelSmall),
          if (canChange)
            Align(alignment:Alignment.centerRight,
              child:Checkbox(
                key:Key('m41-check-${item.id}'),
                value:selected.contains(item.id),
                onChanged:(v)=>setState(() {
                  if(v==true){selected.add(item.id);}
                  else{selected.remove(item.id);}
                }),
              )),
        ])));
  }
}
