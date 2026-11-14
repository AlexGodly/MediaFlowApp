#!/usr/bin/env python3
"""Live check of every keyless metadata / cover source (run by
.github/workflows/live-sources.yml on a GitHub runner, which can reach the
internet). Prints, per source: HTTP status, whether a browser page may read it
(CORS), and the shape of the answer, so the adapters can be checked against
the real services."""
import json, sys, urllib.request, urllib.error

UA = 'MediaFlow/9.0 (+https://github.com/AlexGodly/MediaFlowApp; live source check)'
CHECKS = [
    # The app's 7 cover sources.
    ('steam', 'GET', 'https://store.steampowered.com/api/storesearch/?term=portal&l=english&cc=us', None),
    ('itunes', 'GET', 'https://itunes.apple.com/search?term=abbey%20road&entity=album&limit=2', None),
    ('musicbrainz', 'GET', 'https://musicbrainz.org/ws/2/release-group/?query=releasegroup:%22abbey%20road%22&fmt=json&limit=2', None),
    ('coverartarchive', 'GET', 'https://coverartarchive.org/release-group/9162580e-5df4-32de-80cc-f45a8d8a9b1d', None),
    ('vndb', 'POST', 'https://api.vndb.org/kana/vn', {'filters': ['search', '=', 'clannad'], 'fields': 'title,released,image.url', 'results': 2}),
    ('ifdb', 'GET', 'https://ifdb.org/search?json&game&searchfor=Zork', None),
    ('gutendex', 'GET', 'https://gutendex.com/books?search=frankenstein', None),
    ('googlebooks', 'GET', 'https://www.googleapis.com/books/v1/volumes?q=intitle%3AFrankenstein&maxResults=2', None),
    # Keyless sources not connected yet.
    ('wikidata', 'GET', 'https://www.wikidata.org/w/api.php?action=wbsearchentities&search=Dune&language=en&format=json&origin=*&limit=3', None),
    ('wikidata-entity', 'GET', 'https://www.wikidata.org/w/api.php?action=wbgetentities&ids=Q190192&props=claims%7Clabels&languages=en&format=json&origin=*', None),
    ('wikimedia', 'GET', 'https://commons.wikimedia.org/w/api.php?action=query&list=search&srsearch=Dune%20cover&srnamespace=6&srlimit=3&format=json&origin=*', None),
    ('loc', 'GET', 'https://www.loc.gov/books/?q=frankenstein&fo=json&c=3', None),
    ('crossref', 'GET', 'https://api.crossref.org/works?query.bibliographic=frankenstein&rows=2&filter=type:book', None),
    ('inventaire', 'GET', 'https://inventaire.io/api/search?types=works&search=dune&lang=en&limit=3', None),
    ('episodate', 'GET', 'https://www.episodate.com/api/search?q=breaking%20bad&page=1', None),
    ('episodate-show', 'GET', 'https://www.episodate.com/api/show-details?q=breaking-bad', None),
    ('mangaupdates', 'POST', 'https://api.mangaupdates.com/v1/series/search', {'search': 'berserk', 'perpage': 2}),
    ('deezer', 'GET', 'https://api.deezer.com/search/album?q=abbey%20road&limit=2', None),
    ('dnb', 'GET', 'https://services.dnb.de/sru/dnb?version=1.1&operation=searchRetrieve&query=tit%3Dfaust&recordSchema=oai_dc&maximumRecords=2', None),
    ('bnf', 'GET', 'https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve&query=bib.title%20all%20%22notre%20dame%22&recordSchema=dublincore&maximumRecords=2', None),
    ('vgmdb', 'GET', 'https://vgmdb.info/search/albums?q=final%20fantasy&format=json', None),
    ('gcd', 'GET', 'https://www.comics.org/api/series/name/batman/?format=json', None),
    ('boardgamegeek', 'GET', 'https://boardgamegeek.com/xmlapi2/search?query=catan&type=boardgame', None),
    ('gog', 'GET', 'https://embed.gog.com/games/ajax/filtered?mediaType=game&search=witcher', None),
    ('royalroad', 'GET', 'https://www.royalroad.com/fictions/search?title=mother%20of%20learning', None),
    ('mangadex', 'GET', 'https://api.mangadex.org/manga?title=berserk&limit=2&includes[]=cover_art', None),
    ('openlibrary', 'GET', 'https://openlibrary.org/search.json?title=frankenstein&limit=2', None),
    ('tvmaze', 'GET', 'https://api.tvmaze.com/search/shows?q=breaking%20bad', None),
    ('kitsu', 'GET', 'https://kitsu.io/api/edge/anime?filter[text]=cowboy%20bebop&page[limit]=2', None),
    ('jikan', 'GET', 'https://api.jikan.moe/v4/anime?q=cowboy%20bebop&limit=2', None),
    ('fribb', 'GET', 'https://raw.githubusercontent.com/Fribb/anime-lists/master/anime-list-mini.json', None),
]


def shape(v, depth=0):
    if depth > 3:
        return '…'
    if isinstance(v, dict):
        return {k: shape(x, depth + 1) for k, x in list(v.items())[:14]}
    if isinstance(v, list):
        return [shape(v[0], depth + 1)] if v else []
    if isinstance(v, str):
        return v[:90]
    return v


def run(name, method, url, body):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        'User-Agent': UA, 'Accept': 'application/json, text/xml;q=0.9, */*;q=0.5',
        'Origin': 'https://alexgodly.github.io', **({'Content-Type': 'application/json'} if data else {})})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            raw = r.read(400000)
            status, cors, ctype = r.status, r.headers.get('Access-Control-Allow-Origin'), r.headers.get('Content-Type', '')
    except urllib.error.HTTPError as e:
        raw, status, cors, ctype = e.read(2000), e.code, e.headers.get('Access-Control-Allow-Origin'), e.headers.get('Content-Type', '')
    except Exception as e:  # noqa: BLE001
        print(f'### {name}: FAILED {type(e).__name__}: {e}')
        return
    text = raw.decode('utf-8', 'replace')
    print(f'### {name}: HTTP {status} · CORS {cors!r} · {ctype}')
    try:
        print(json.dumps(shape(json.loads(text)), ensure_ascii=False)[:2500])
    except Exception:  # noqa: BLE001
        print(text[:1500].replace('\n', ' '))


if __name__ == '__main__':
    only = set(sys.argv[1:])
    for c in CHECKS:
        if not only or c[0] in only:
            run(*c)
