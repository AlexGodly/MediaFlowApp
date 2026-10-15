import 'package:flutter/material.dart';

import '../../data/mediaflow_models.dart';
import '../../services/native_m42_mixed_queue.dart';
import '../../services/native_m43_recommendation_audit.dart';
import 'native_m43_recommendation_audit_panel.dart';

/// Read-only v287/v368 Personal Order queue. This is NOT the task generator:
/// no traversal staging, assignment rule edits, or cloud changes occur here.
class NativeM42MixedQueuePanel extends StatefulWidget {
  const NativeM42MixedQueuePanel({super.key,required this.catalog});
  final MediaFlowCatalog catalog;

  @override
  State<NativeM42MixedQueuePanel> createState() =>
      _NativeM42MixedQueuePanelState();
}

class _NativeM42MixedQueuePanelState extends State<NativeM42MixedQueuePanel> {
  String categoryId='',search='';
  String? focusedToken;
  final TextEditingController queueSearch=TextEditingController();
  late NativeM42MixedQueues reader;
  late NativeM43RecommendationAudit audit;
  int page=0;

  @override
  void initState() {
    super.initState();
    reader=NativeM42MixedQueues(widget.catalog);
    audit=NativeM43RecommendationAudit(widget.catalog,reader:reader);
  }

  @override
  void dispose() {
    queueSearch.dispose();
    super.dispose();
  }

  void _inspectSource(String category,String token) {
    queueSearch.clear();
    setState(() {
      categoryId=category;
      search='';
      focusedToken=token;
      page=0;
    });
  }
  static const pageSize=30;

  @override
  void didUpdateWidget(covariant NativeM42MixedQueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.catalog,widget.catalog)) {
      page=0;
      focusedToken=null;
      reader=NativeM42MixedQueues(widget.catalog);
      audit=NativeM43RecommendationAudit(widget.catalog,reader:reader);
    }
  }

  Widget _poster(MediaFlowTitle title) => title.coverUrl.isEmpty
      ? const Icon(Icons.book_outlined,size:24)
      : Image.network(title.coverUrl,width:38,height:54,
          fit:BoxFit.cover,
          errorBuilder:(context,error,stackTrace)=>
            const Icon(Icons.book_outlined,size:24));

  Widget _direct(NativeM42QueueSlot slot) {
    final title=slot.title;
    return Card(
      key:Key('m42-slot-${slot.token}'),
      child:ListTile(
        leading:CircleAvatar(
          child:Text('${slot.position}')),
        title:Text(title?.title ?? 'Unavailable Library title',
          maxLines:2,overflow:TextOverflow.ellipsis),
        subtitle:Text(slot.candidates.isNotEmpty
            ? 'Direct title · Recommendation #'
                '${slot.candidates.first.recommendationIndex}'
            : 'Direct title · Not currently eligible'),
        trailing:title==null ? const Icon(Icons.warning_amber_outlined)
            : _poster(title),
      ),
    );
  }

  Widget _collection(NativeM42QueueSlot slot) {
    final assignment=slot.assignment, collection=slot.collection;
    return Card(
      key:Key('m42-slot-${slot.token}'),
      child:ExpansionTile(
        key:focusedToken==slot.token
            ? Key('m43-focused-${slot.token}')
            : Key('m42-collection-${slot.token}'),
        initiallyExpanded:focusedToken==slot.token,
        leading:CircleAvatar(child:Text('${slot.position}')),
        title:Text(collection?.title ?? 'Unavailable Collection',
          maxLines:2,overflow:TextOverflow.ellipsis),
        subtitle:Text(assignment==null ?
          'Unavailable Collection assignment' :
          'Collection block · ${slot.candidates.length} eligible · '
          '${assignment.categoryRule} category · '
          '${assignment.completedRule} completed'),
        children:[
          if (slot.candidates.isEmpty)
            const ListTile(
              title:Text('No eligible titles in this Collection queue block.'),
              subtitle:Text('This does not delete or re-rank the block.')),
          for (final entry in slot.candidates)
            ListTile(
              key:Key('m42-member-${entry.assignmentId}-${entry.title.id}'),
              contentPadding:const EdgeInsets.symmetric(horizontal:12),
              leading:_poster(entry.title),
              title:Text(entry.title.title,maxLines:2,
                overflow:TextOverflow.ellipsis),
              subtitle:Text('Collection member #${entry.collectionPosition}'
                ' · Recommendation #${entry.recommendationIndex}'),
              trailing:Text('Slot ${entry.outerPosition}'),
            ),
          const Padding(
            padding:EdgeInsets.all(10),
            child:Text('The Collection occupies one queue slot. Titles are '
              'followed in their saved Collection order, subject to category, '
              'completion, traversal and duplicate suppression rules.'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories=reader.categoryIds;
    if (categories.isEmpty) {
      return const Center(child:Text('No Personal Order categories available.'));
    }
    final current=categories.contains(categoryId) ? categoryId : categories.first;
    final categoryAudit=audit.forCategory(current);
    final all=categoryAudit.slots;
    final query=search.trim().toLowerCase();
    final visible=<NativeM42QueueSlot>[];
    for(final slot in all) {
      if (focusedToken!=null && focusedToken!=slot.token) { continue; }
      if (query.isNotEmpty &&
          !(slot.title?.searchText.contains(query) ?? false) &&
          !(slot.collection?.title.toLowerCase().contains(query) ?? false) &&
          !slot.candidates.any((entry)=>
            entry.title.searchText.contains(query))) {
        continue;
      }
      visible.add(slot);
    }
    final pages=visible.isEmpty?1:(visible.length+pageSize-1)~/pageSize;
    final currentPage=page.clamp(0,pages-1);
    final shown=visible.skip(currentPage*pageSize).take(pageSize).toList();
    final diagnostics=reader.diagnosticsForCategory(current);
    final recommendationCount=categoryAudit.recommendations.length;
    final name={
      for(final category in widget.catalog.categories)
        category.id:category.name,
    };
    return Column(
      crossAxisAlignment:CrossAxisAlignment.stretch,
      children:[
        const Padding(
          padding:EdgeInsets.only(bottom:8),
          child:Text(
            'READ-ONLY · Category queue slots and Collection blocks. '
            'No edits, XP, History changes or cloud save.',
            key:Key('m42-readonly-disclaimer')),
        ),
        Wrap(spacing:12,runSpacing:8,
          crossAxisAlignment:WrapCrossAlignment.center,children:[
          DropdownButton<String>(
            key:const Key('m42-category'),
            value:current,
            items:[
              for(final cid in categories)
                DropdownMenuItem(value:cid,
                  child:Text(name[cid]??cid,
                    overflow:TextOverflow.ellipsis)),
            ],
            onChanged:(v) {
              if (v!=null) {
                queueSearch.clear();
                setState(() {
                  categoryId=v; page=0;
                  search=''; focusedToken=null;
                });
              }
            }),
          Text('${all.length} queue slots · '
            '$recommendationCount eligible recommendations',
            key:const Key('m42-queue-count')),
        ]),
        TextField(
          controller:queueSearch,
          key:const Key('m42-search'),
          decoration:const InputDecoration(
            labelText:'Find direct titles or Collections in this queue',
            border:OutlineInputBorder(),prefixIcon:Icon(Icons.search),
            isDense:true),
          onChanged:(v)=>setState(() {
            search=v;page=0;focusedToken=null;
          }),
        ),
        ConstrainedBox(
          constraints:const BoxConstraints(maxHeight:230),
          child:SingleChildScrollView(
            child:NativeM43RecommendationAuditPanel(
              audit:audit,categoryId:current,onJump:_inspectSource),
          ),
        ),
        if (focusedToken!=null)
          Align(
            alignment:Alignment.centerLeft,
            child:TextButton.icon(
              key:const Key('m43-clear-focus'),
              onPressed:()=>setState(() {
                focusedToken=null;page=0;
              }),
              icon:const Icon(Icons.view_list_outlined),
              label:Text('Showing queue slot ${all.where((s)=>s.token==focusedToken).firstOrNull?.position ?? "?"} · View all slots'),
            ),
          ),
        if (diagnostics.isNotEmpty)
          ExpansionTile(
            key:const Key('m42-queue-diagnostics'),
            title:Text('${diagnostics.length} queue reference warning(s)'),
            leading:const Icon(Icons.warning_amber_outlined),
            children:[
              for (final warning in diagnostics)
                ListTile(dense:true,title:Text(warning)),
            ],
          ),
        const SizedBox(height:8),
        Expanded(child:visible.isEmpty
          ? Center(child:Text(all.isEmpty
              ? 'No saved mixed queue entries in this category.'
              : 'No queue entries match this search.'))
          : ListView.builder(
              key:const Key('m42-mixed-queue-entries'),
              itemCount:shown.length,
              itemBuilder:(context,index) {
                final slot=shown[index];
                return slot.isCollection ?
                  _collection(slot) : _direct(slot);
              },
            )),
        Row(mainAxisAlignment:MainAxisAlignment.center,children:[
          IconButton(
            key:const Key('m42-previous-page'),
            tooltip:'Previous queue page',
            onPressed:currentPage==0?null:
              ()=>setState(()=>page=currentPage-1),
            icon:const Icon(Icons.chevron_left)),
          Text('Queue page ${currentPage+1} of $pages'),
          IconButton(
            key:const Key('m42-next-page'),
            tooltip:'Next queue page',
            onPressed:currentPage+1>=pages?null:
              ()=>setState(()=>page=currentPage+1),
            icon:const Icon(Icons.chevron_right)),
        ]),
        const Text(
          'Slot numbers are within the selected category. '
          'A Collection is one outer position; its member number is separate. '
          'Recommendation positions exclude ineligible/traversed titles.',
          textAlign:TextAlign.center),
      ],
    );
  }
}
