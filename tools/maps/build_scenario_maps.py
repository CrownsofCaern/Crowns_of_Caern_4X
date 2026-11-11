"""Build original scenario maps; mission rules remain in the generated JSON.
Optional goals are gated for week one (ScenarioGating): the forge, the watch and the
envoy open in the second week, the siege camp and the relic keeper outfight the
combined starting army.
Run: python3 tools/maps/build_scenario_maps.py
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
W, H = 52, 37
terrain = [['^'] * W for _ in range(H)]
roads = []
def rect(x0, y0, x1, y1, biome='.'):
    for y in range(y0, y1+1):
        for x in range(x0, x1+1):
            terrain[y][x] = biome

def road(a, b):
    assert a[0] == b[0] or a[1] == b[1]
    rect(min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))
    roads.append({'from':list(a), 'to':list(b)})

# The north tunnel is a shortcut. The eastern road remains open when it is sealed.
for a,b in [((6,6),(6,30)),((6,18),(23,18)),((23,6),(23,30)),
            ((23,6),(47,6)),((23,30),(47,30)),((40,6),(40,30)),
            ((20,11),(20,18)),((6,30),(13,30)),((32,6),(32,11)),
            ((32,30),(32,25)),((6,12),(12,12))]:
    road(a,b)
for box in [(2,14,10,22,'.'),(3,3,9,8,'f'),(20,3,26,8,'.'),
            (43,3,49,9,'i'),(43,27,49,33,'i'),(20,27,26,33,'r'),
            (18,10,21,13,'r'),(30,9,34,12,'f'),(30,24,34,27,'i'),
            (9,10,14,13,'r'),(3,27,9,33,'w')]:
    rect(*box)
# Restore road tiles through the biome rooms without widening the tunnel.
# The relic pocket is marshland beneath its road; keep its single guarded entrance.
terrain[30][12] = 'w'
terrain[30][13] = 'w'
# The relic lies in an open marsh clearing; its keeper stands beside it and the
# guard rule (an adjacent army guards a prize) keeps it out of reach.
rect(10, 29, 15, 31, 'w')
objects=[]
def obj(id,object_type,x,y,**fields):
    out={'id':id,'type':object_type,'pos':[x,y],**fields};objects.append(out);return out

def town(id,x,y,name,owner,built=None,garrison=None):
    return obj(id,'town',x,y,name=name,town_type='concord',owner=owner,
               built=built or ['c_hall','c_tavern','c_dw1'],garrison=garrison or [])

castle=town('town_last_watch',6,18,'Last Watch',0,['c_hall','c_tavern','c_market','c_dw1','c_dw2','c_dw3','c_palisade'],[['pike_militia',12],['longbowman',8]])
town('town_northwatch',23,6,'Northwatch',0,garrison=[['pike_militia',12]])
town('town_crossing',13,18,'Crossingstead',0,garrison=[['pike_militia',10]])
ally=town('town_reedhaven',6,6,'Reedhaven',-1)
ally['requires_quest']='reedhaven_pact'
obj('tunnel_north','gate',23,12,name='North Tunnel',closed=False,sprite='place_cindermaw_gate')
obj('site_nest','scenario_site',20,11,name='The Hollow Nest',kind='nest',gate='tunnel_north',owner=-1,
    sprite='encounter_thornwolf_den',guard=[['crag_slinger',16],['hill_giant',2]],
    text='Clear this nest, then seal its tunnel. Northern invaders must march around the eastern ridge.')
obj('site_pact','scenario_site',8,6,name='Reedhaven Envoy',kind='quest',quest='reedhaven_pact',unlock_day=9,
    sprite='encounter_free_company_camp',text='The people of Reedhaven will stand with you if you return their stolen oath relic. Their envoy arrives on day 9.')
obj('guardian_oath','neutral_army',12,30,name='Keeper of the Drowned Oath',stacks=[['bog_lurker',26],['marsh_hag',13]])
obj('relic_oath','quest_item',13,30,name='The Reed Oathstone',item='reed_oathstone',guarded_by='guardian_oath',sprite='object_chest')
obj('site_watch','scenario_site',32,11,name='The Broken Watch',kind='watchtower',owner=-1,
    sprite='place_fenwick_dike',guard=[['road_cutthroat',14]],unlock_day=8,text='Restore this watch for earlier invasion warnings and a view of the entry roads. Its keepers return on day 8.')
obj('site_camp','scenario_site',32,25,name='Ashen Supply Camp',kind='siege_camp',owner=-1,
    sprite='encounter_ash_pit_champion',guard=[['cinderling',84],['brimstone_hurler',34]],text='Destroy the supplies to reduce every future invasion army by one fifth.')
obj('site_forge','scenario_site',12,12,name='The Abandoned Forge',kind='forge',owner=-1,
    sprite='mine_ore',guard=[['crag_slinger',12]],unlock_day=8,text='Secure the workshops to send eight pike militia to Last Watch every week. The smiths return on day 8.')
for id,x,y,res,amount in [('mine_watch_wood',4,15,'wood',2),('mine_watch_ore',9,21,'ore',2),('mine_watch_gold',23,29,'gold',500)]:
    obj(id,'mine',x,y,resource=res,owner=0,amount=amount)
for id,x,y,res,amount in [('supply_west',6,25,'gold',1200),('supply_north',18,18,'wood',8),('supply_east',35,6,'ore',8)]:
    obj(id,'resource',x,y,resource=res,amount=amount)
players=[{'id':0,'name':'The Last Watch','faction':'concord','color':'#4488d0','is_human':True},
         {'id':1,'name':'The Encircling Host','faction':'ashen','color':'#c94040','is_human':False},
         {'id':2,'name':'Reedhaven','faction':'concord','color':'#49a85a','is_human':False}]
heroes=[{'id':'hero_watch','name':'Aldous Wren','class':'knight','owner':0,'pos':[6,18],
         'army':[['pike_militia',24],['longbowman',14],['shieldwarden',8]]},
        {'id':'hero_scout','name':'Maelis Thorne','class':'ranger','owner':0,'pos':[7,18],
         'army':[['longbowman',10],['pike_militia',12]]}]
profiles=[('The Ember Scout',7,[47,6],[['cinderling',16],['scorchhound',5]],'town_northwatch'),
          ('The Ashen Hunter',14,[47,30],[['cinderling',28],['scorchhound',9],['brimstone_hurler',7]],'town_last_watch'),
          ('The Cinder Marshal',21,[47,6],[['flayer',15],['brimstone_hurler',14],['scorchhound',15]],'town_northwatch'),
          ('The Northern Hammer',28,[47,6],[['flayer',25],['brimstone_hurler',25],['gorgewing',6]],'town_northwatch'),
          ('The Southern Flame',28,[47,30],[['cinderling',70],['scorchhound',28],['ash_witch',8]],'town_last_watch'),
          ('The Last Pyre',35,[47,6],[['flayer',28],['brimstone_hurler',24],['pyre_titan',4]],'town_last_watch'),
          ('The Red Hand',35,[47,30],[['scorchhound',32],['ash_witch',9],['gorgewing',6]],'town_crossing')]
waves=[]
for i,(name,day,spawn,army,target) in enumerate(profiles):
    waves.append({'id':f'watch_wave_{i}','day':day,'warning_days':3,'owner':1,'spawn':spawn,
                  'entry_tiles':[[spawn[0]+dx,spawn[1]] for dx in range(3)],
                  'entry_name':'the North Road' if spawn[1]==6 else 'the South Road','target':target,
                  'targets':[target,'town_last_watch','town_crossing','town_northwatch'],'order':'assault',
                  'hero':{'id':f'watch_commander_{i}','name':name,'class':'warlord','army':army}})
scenario={'name':'The Last Watch','mode':'survival','player':0,'castle':'town_last_watch',
          'briefing':'Hold Last Watch through the final siege. Armies approach along the north and south roads. Leave the walls to win Reedhaven, seal the north tunnel, restore the watch, or destroy the siege supplies.',
          'protected_towns':['town_last_watch'],'invasion_players':[1],'dormant_players':[2],
          'max_active_invaders':6,'random_events':False,'wave_strength':{'easy':0.75,'normal':1.0,'hard':1.25},
          'objectives':[{'id':'hold','type':'survive','through_day':35,'text':'Hold Last Watch through day 35.'},
                        {'id':'siege','type':'clear_waves','text':'Defeat every invasion commander, including the final siege.'}],
          'waves':waves,'forge_support':{'town':'town_last_watch','creature':'pike_militia','count':8},
          'quests':[{'id':'reedhaven_pact','giver':'site_pact','item':'reed_oathstone',
                     'text':'Defeat the Keeper in the southern marsh, recover the Reed Oathstone from the chest behind it, and return it here.',
                     'reward':{'town':'town_reedhaven','ally_player':2,'defend_target':'town_northwatch','resources':{'gold':1200},
                               'hero':{'id':'hero_reedwarden','name':'Cerrid Reedwarden','class':'knight','army':[['pike_militia',24],['longbowman',12]]},
                               'weekly':{'town':'town_last_watch','creature':'longbowman','count':8}},
                     'completion_text':'Reedhaven joins your cause. Its warden defends Northwatch, and eight longbowmen reinforce Last Watch each week.'}]}
result={'id':'last_watch','name':'The Last Watch — Survival','width':W,'height':H,
        'terrain':[''.join(row) for row in terrain],'roads':roads,'players':players,'heroes':heroes,'objects':objects,'scenario':scenario}
(ROOT/'data/maps/last_watch.json').write_text(json.dumps(result,indent=2)+'\n')
print('Built last_watch.json')
