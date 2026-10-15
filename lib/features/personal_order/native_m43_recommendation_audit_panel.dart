import 'package:flutter/material.dart';

import '../../services/native_m43_recommendation_audit.dart';

/// Native queue evidence only; it intentionally never advances a task,
/// updates traversal, changes priority, or writes cloud account state.
class NativeM43RecommendationAuditPanel extends StatefulWidget {
  const NativeM43RecommendationAuditPanel({
    super.key,required this.audit,required this.categoryId,
    required this.onJump,
  });
  final NativeM43RecommendationAudit audit;
  final String categoryId;
  final void Function(String categoryId,String token) onJump;

  @override
  State<NativeM43RecommendationAuditPanel> createState() =>
      _NativeM43RecommendationAuditPanelState();
}

class _NativeM43RecommendationAuditPanelState
    extends State<NativeM43RecommendationAuditPanel> {
  String query='',selectedId='',excludedText='';

  @override
  void didUpdateWidget(covariant NativeM43RecommendationAuditPanel old) {
    super.didUpdateWidget(old);
    if(!identical(old.audit,widget.audit)) {
      selectedId='';
      excludedText='';
    }
  }

  @override
  Widget build(BuildContext context) {
    final category=widget.audit.forCategory(widget.categoryId);
    final first=category.firstEligible();
    final scoped=widget.audit.priorityEnabled;
    final priorityMessage=switch(scoped) {
      true=>'Personal Order prioritization enabled for the saved snapshot. '
        'Actual task selection still depends on the task category and '
        'the website task generator.',
      false=>'Personal Order prioritization disabled in the saved snapshot. '
        'The website uses its existing fallback title picker.',
      null=>'Personal Order priority setting not present in this snapshot. '
        'No assertion about which picker was used.',
    };
    final excluded=<String>{
      for(final id in excludedText.split(RegExp(r'[,\s]+')))
        if(id.trim().isNotEmpty) id.trim(),
    };
    final afterExcluded=excluded.isEmpty ? null :
      widget.audit.firstEligibleWithExclusions(widget.categoryId,excluded);
    final results=widget.audit.searchTitles(query);
    final placements=selectedId.isEmpty ?
      const <NativeM43TitlePlacement>[] :
      widget.audit.placementsForTitle(selectedId);
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Card(
        key:const Key('m43-first-eligible'),
        child:Padding(
          padding:const EdgeInsets.all(10),
          child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text('First eligible Personal Order candidate',
                style:Theme.of(context).textTheme.titleSmall),
              const SizedBox(height:4),
              Text(first==null ? 'None in this category queue.' :
                '${first.title.title} · recommendation #'
                '${first.recommendationIndex} · outer slot '
                '#${first.outerPosition} · '
                '${first.fromCollection?"Collection":"Direct title"}',
                key:const Key('m43-first-label'),
                maxLines:3,overflow:TextOverflow.ellipsis),
              const SizedBox(height:3),
              Text(priorityMessage,
                style:Theme.of(context).textTheme.bodySmall),
              if(first!=null)
                Align(alignment:Alignment.centerRight,
                  child:TextButton.icon(
                    key:const Key('m43-jump-first'),
                    icon:const Icon(Icons.near_me_outlined,size:18),
                    label:const Text('Inspect source slot'),
                    onPressed:()=>widget.onJump(widget.categoryId,
                      ' ${first.fromCollection?'c:':'t:'}'
                      '${first.fromCollection?first.assignmentId:first.title.id}'
                        .trim()),
                  )),
            ],
          ),
        ),
      ),
      ExpansionTile(
        key:const Key('m43-ranking-explorer'),
        tilePadding:EdgeInsets.zero,
        leading:const Icon(Icons.manage_search),
        title:const Text('Title placements & recommendation audit'),
        subtitle:Text('${category.recommendations.length} eligible · '
          '${category.ineligibleOccurrences} skipped references · '
          '${category.unresolvedMembers} unresolved'),
        children:[
          TextField(
            key:const Key('m43-preview-exclusions'),
            decoration:const InputDecoration(
              labelText:'Excluded title IDs (preview only)',
              helperText:'v180-style exclusion preview; '
                'not a real reroll or task mutation',
              isDense:true,border:OutlineInputBorder()),
            onChanged:(v)=>setState(()=>excludedText=v),
          ),
          if(excluded.isNotEmpty)
            ListTile(
              key:const Key('m43-exclusion-result'),
              dense:true,
              title:Text(afterExcluded==null
                ? 'No remaining eligible queue title'
                : 'After exclusions: ${afterExcluded.title.title}'),
              subtitle:const Text('Does not simulate fallback or task selection.'),
            ),
          const SizedBox(height:8),
          TextField(
            key:const Key('m43-rank-search'),
            decoration:const InputDecoration(
              labelText:'Find any title by name or ID',
              prefixIcon:Icon(Icons.search),isDense:true,
              border:OutlineInputBorder()),
            onChanged:(v)=>setState(() {
              query=v;
              selectedId='';
            }),
          ),
          if(query.trim().isNotEmpty)
            ConstrainedBox(
              constraints:const BoxConstraints(maxHeight:205),
              child:results.isEmpty
                ? const ListTile(title:Text('No matching Library titles.'))
                : ListView.builder(
                    shrinkWrap:true,
                    itemCount:results.length,
                    itemBuilder:(context,i) {
                      final item=results[i];
                      return ListTile(
                        dense:true,
                        key:Key('m43-title-${item.id}'),
                        title:Text(item.title,maxLines:1,
                          overflow:TextOverflow.ellipsis),
                        subtitle:Text(item.id),
                        trailing:selectedId==item.id ?
                          const Icon(Icons.check_circle_outline) :
                          const Icon(Icons.chevron_right),
                        onTap:()=>setState(()=>selectedId=item.id),
                      );
                    }),
            ),
          if(selectedId.isNotEmpty)...[
            const SizedBox(height:6),
            Text(placements.isEmpty
              ? 'No known eligible or skipped queue placements for '
                  'this title.'
              : '${placements.length} saved position(s) across '
                  'category queues',
              key:const Key('m43-placement-count')),
            ConstrainedBox(
              constraints:const BoxConstraints(maxHeight:245),
              child:ListView.builder(
                shrinkWrap:true,
                itemCount:placements.length,
                itemBuilder:(context,i) {
                  final p=placements[i];
                  final categoryName=widget.audit.catalog.categories
                    .where((c)=>c.id==p.categoryId)
                    .firstOrNull?.name??p.categoryId;
                  return ListTile(
                    key:Key('m43-placement-${p.categoryId}-${p.token}'),
                    dense:true,
                    title:Text('$categoryName · queue slot '
                      '#${p.slotPosition}'
                      '${p.fromCollection ? " · member #${p.memberPosition}" : ""}'),
                    subtitle:Text(
                      '${p.eligible ? "Recommendation #${p.recommendationIndex}" : p.reason}'
                      ' · direct saved #${p.directSavedPosition==0?"—":p.directSavedPosition}'
                      '${p.fromCollection ? " · ${p.collectionName}" : ""}',
                      maxLines:3,overflow:TextOverflow.ellipsis),
                    trailing:IconButton(
                      key:Key('m43-jump-${p.categoryId}-${p.token}'),
                      tooltip:'Inspect category queue slot',
                      icon:const Icon(Icons.open_in_new),
                      onPressed:()=>widget.onJump(p.categoryId,p.token),
                    ),
                  );
                },
              ),
            ),
          ],
          const Padding(
            padding:EdgeInsets.symmetric(vertical:8),
            child:Text('These are explainable queue positions, not '
              'a universal title rank. A title can appear in multiple '
              'Collection/category assignments and be skipped for '
              'different reasons. No queue or traversal is changed.'),
          ),
        ],
      ),
    ]);
  }
}
