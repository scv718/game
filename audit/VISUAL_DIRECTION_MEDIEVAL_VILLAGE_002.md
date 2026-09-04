# Medieval Frontier Village — Visual Direction 002

이 문서는 `city16.fbx` Asset Zoo의 실제 silhouette와 현재 runtime 화면을 기준으로 한 구현 전 공간 설계다. 카메라, gameplay owner, navigation, building API는 변경 대상으로 보지 않는다.

## 1. Selected Asset Mapping

모든 Cuteskull 후보의 source는 `res://assets/cuteskull-medieval-city/city16.fbx`다.

| Gameplay role | Selected visual assembly | Environment storytelling |
|---|---|---|
| Keep | `Church_2` main hall + `Castle_Tower_3` landmark tower + `Castle_Tower_1/2` secondary towers + short `Castle_Wall` runs + west-facing `Castle_Entrance` | 단일 대형 주택이 아니라, 기존 석조 홀 주위에 방어 시설이 단계적으로 증축된 fortified manor compound로 구성한다. 밝은 지붕은 가능한 기존 material의 muted/slate variation 또는 local material override로 억제한다. |
| Tavern | `House_3_1` | 넓은 frontage와 ㄷ자형 실루엣을 활용한다. `Barrel`, 작은 `Market_1` awning, bench/table 대체 소품, 장작·등불이 있는 흙마당으로 역할을 읽힌다. |
| Inn | `House_7_1` | 가장 긴 민간 건물 중 하나를 선택한다. `Cart_1`, `Sack`, `Wood_Fence_1`, 말·짐을 위한 side yard로 여관/숙박 기능을 표현한다. |
| Blacksmith | `House_5_1` | 작은 본채보다 열린 작업장이 주인공이다. Cuteskull `Cart`, `Barrel`, `Post`와 Quaternius anvil/tool/woodpile/forge-light를 결합한다. |
| Grocery | `House_4_1` + `Market_1_1` or `Market_2_1` | 도로를 향한 작은 점포 전면, `Food_Box_1~3`, `Basket`, `Sack`으로 식료품점임을 표현한다. |
| Market | `Market_1_1~6`, 선택적으로 `Market_2_1~6` | 광장 전체를 균일한 stall ring으로 두지 않는다. 통행량이 높은 광장 남서 가장자리에 3~4개만 비정렬로 배치한다. |
| Residential A | `House_1_1/1_2` | 초기 정착기의 작은 cottage. 작은 garden과 낮은 fence를 붙인다. |
| Residential B | `House_2_1/2_2/2_3` | 중간 규모 가족 주택. 골목 굴곡에 맞춰 입구 방향을 달리한다. |
| Residential C | `House_4_2`, `House_5_2/5_3` | 외곽 생산가구. 장작, cart, 작은 작업마당과 연결한다. |
| Wall | `Castle_Wall` | Portal 방향의 짧은 frontier curtain wall. 마을 전체를 둘러싸지 않는다. |
| Gate | `Castle_Entrance` | 실제 arch와 stone mass가 읽히는 main gate. 방어축과 main street의 시작점이다. |
| Tower | `Castle_Tower_3/4` main, `Castle_Tower_1/2` secondary | 높은 3/4는 gate terminal 또는 Keep landmark에 제한 사용한다. 작은 1/2는 flank/inner compound에 사용한다. 반복 tower spam은 금지한다. |

`Castle_Wall_Door`와 `Castle_Tower_Door`는 landmark가 아니라 연결부/보조 입구로만 사용한다. `Church_1/2`를 종교시설 그대로 복제하지 않고 Keep의 central hall shell로 한 번만 사용한다.

## 2. Macro Layout — 정착지가 성장한 이유

이 정착지는 동쪽 물가의 안전한 식수와 서쪽 Portal 위협 사이에 생긴 군사 보급 거점이다.

1. 가장 오래된 구조는 동쪽 물가의 높은 지반에 세운 fortified manor, 즉 Keep이다. 강/호수는 Keep의 자연 해자이며, 서쪽 출입구만 방어하면 된다.
2. Portal 활동이 시작된 뒤 서쪽의 가장 좁은 접근부에 wall과 gate를 세웠다. 성벽은 거대한 도시 외곽선이 아니라 위험 방향만 막는 전면 방어선이다.
3. gate와 Keep을 오가는 보급 동선이 main street가 되었다. 길은 지형과 물웅덩이를 피해 완만하게 굽고, 오래 머무는 지점이 넓어져 plaza가 되었다.
4. blacksmith와 tavern은 병력과 상인이 가장 먼저 만나는 gate 쪽 길가에 생겼다. grocery와 market은 Keep과 민가가 함께 접근할 수 있는 plaza 가장자리에 자리 잡았다.
5. 주거지는 상점 뒤쪽의 비교적 조용한 side lanes를 따라 두세 채씩 증가했다. 집들은 중심점을 보지 않고 각자의 길·마당을 바라본다.
6. 농장은 물과 평탄지가 있는 남동쪽, lumberyard는 숲과 main road 사이, quarry는 암반이 드러난 북동쪽 외곽에 자리 잡는다.

상대적 화면 구조는 다음과 같다.

```text
WEST / DANGER                                           EAST / SUPPLY

Portal -- corrupted basin -- battlefield -- wall / gate
                                               |
                                      inner staging yard
                                               |
                              blacksmith -- curved main street -- tavern
                                               |
                                 market edge -- plaza -- short bridge
                                                   |             |
                                          residential lanes   Keep compound
                                                   |             |
                                      farm / lumberyard -- water -- forest / quarry
```

## 3. Main Road / Secondary Road Structure

- Gate approach: 7–8m 정도의 넓은 군사 접근로. Portal에서 gate까지는 마차와 병력이 회전할 수 있지만 장식은 드물다.
- Inner staging yard: gate 안쪽 10–14m 깊이의 비정형 공터. main street가 즉시 건물 사이로 끼어들지 않는다.
- Main street: staging yard에서 남동쪽으로 약간 휘었다가 plaza로 돌아오는 5–7m 폭의 길. 폭과 가장자리가 일정하지 않으며 wheel rut, worn dirt, grass intrusion을 섞는다.
- Plaza: 원형 disc가 아니라 여러 동선이 겹쳐 넓어진 비대칭 stone/worn-ground pocket. Keep bridge와 market frontage가 서로 다른 각도로 접한다.
- Keep approach: plaza에서 물의 좁은 지점을 건너는 짧은 stone/timber bridge와 직선에 가까운 ceremonial approach. 이 구간만 의도적으로 정돈한다.
- Secondary lanes: service building 사이를 빠져나가는 3–4m 굽은 길. residential cluster로 갈수록 2–2.5m 골목과 잔디길이 된다.
- Production track: plaza 남동부에서 farm과 lumberyard로 갈라지는 마차길. quarry 길은 물가를 따라 북동쪽으로 상승한다.

도로는 큰 BoxMesh 띠를 연결하지 않는다. Ground 계열 texture를 projector/decal-like irregular mesh 또는 짧은 spline ribbon에 타일링하고, 폭·edge alpha·색을 구간별로 바꾼다.

## 4. Keep / Gate Defensive Axis

`Portal → battlefield → gate → staging yard → main street → plaza → bridge → Keep entrance`가 한 프레임에서 끊김 없이 읽혀야 한다.

Gate는 wall의 정확한 수학적 중앙에서 약간 벗어나 지형의 실제 통과 지점을 점유한다. 양쪽 wall 길이와 tower 높이는 동일하지 않다. battlefield 쪽에는 barricade와 sparse post만 두고 충분한 전투공간을 남긴다.

Keep은 물의 오른쪽/east bank에 두고 entrance를 서쪽으로 향하게 한다. main hall을 중심으로 tower와 짧은 wall이 완전히 대칭이 아닌 작은 courtyard를 만든다. Keep 앞 10–14m는 stone forecourt로 비우며 일반 주택, 시장 stall, 농업 소품을 넣지 않는다. 강과 bridge 때문에 Keep은 마을 중심에 섞인 큰 집이 아니라 마지막 방어지점으로 읽힌다.

## 5. Terrain Material Plan

| Zone | Base asset/material direction | Visual treatment |
|---|---|---|
| Village grass | `Grass_1/2` + project-local muted grass material | 단일 밝은 초록을 피하고 olive/gray-green variation을 넓고 약하게 섞는다. |
| Worn village ground | `Ground_1`, `Ground_1_Alpha` | 건물 출입구와 마당 중심에 불규칙하게 사용한다. district 전체를 덮지 않는다. |
| Dirt road | `Ground_1/2` texture-derived local material | 낮은 대비의 흙, wheel rut, 가장자리 grass 침입. 직사각형 외곽이 보이지 않게 한다. |
| Stone plaza / Keep court | `City_Ground`, 제한적 `Ground_Bricks` | plaza는 warm gray, Keep court는 cooler gray로 차등화한다. |
| Farm ground | `Ground_2`를 더 어둡고 따뜻하게 변형 | crop bed 단위의 토양과 휴경 잔디를 번갈아 둔다. 거대한 갈색 평면은 금지한다. |
| Quarry | `Stone_1~4` + desaturated `City_Ground` | 바위 크기와 높이를 계단식으로 쌓아 cliff edge를 만들고, 바닥은 작은 stone scatter로 전이한다. |
| Battlefield | `Ground_3` 계열을 dry gray-brown으로 변형 | 중앙은 비워 전투 가독성을 유지하고 가장자리만 debris/dead vegetation으로 닫는다. |
| Corruption | `Ground_3_Alpha` 또는 local dark material | charcoal-purple 톤과 제한된 emissive cracks. 완전한 검은 polygon 경계는 피한다. |
| Water | Cuteskull `Water` material/texture | 길고 직선인 ribbon이 아니라 폭이 변하는 lake/stream silhouette. 둔덕, stone, grass가 shoreline을 가린다. |

## 6. Residential Cluster Plan

- North lane cluster: plaza 북서쪽의 오래된 3채. 작은 House A/B가 서로 다른 setback을 가지며 공동 우물과 laundry/garden을 공유한다.
- South garden cluster: plaza 남쪽의 3~4채. 길은 두 번 굽고 각 집에는 울타리가 완전히 닫히지 않은 개인 마당이 있다.
- Production-edge homes: farm/lumberyard 쪽 2채. 본채보다 cart, straw, wood stack이 있는 작업마당이 넓다.
- Riverside는 floodplain과 Keep sightline을 위해 드물게 유지한다. 물가를 집으로 채우지 않고 grazing grass, willow-like tree group, stone bank로 남긴다.

건물 간격은 동일하지 않다. 작은 집 3–5m, 큰 집 5–8m를 기본으로 하되 마당·나무·고저차가 있으면 더 벌린다. 모든 입구는 가장 가까운 lane 또는 yard를 향한다.

## 7. Service Building Frontage Plan

- Blacksmith: gate staging yard 뒤 첫 번째 main-street bend. 불과 소음 때문에 주거지에서 떨어지고, 열린 dirt work yard가 road를 향한다.
- Tavern: gate와 plaza 사이 바깥쪽 curve. barrel과 seating은 길을 막지 않는 넓어진 shoulder에 둔다.
- Grocery: plaza 진입부. 본채 정면과 1개 stall이 길을 향하고 food boxes가 side wall을 따라 쌓인다.
- Market: plaza 남서 edge에 3~4개 stall을 서로 다른 깊이와 각도로 배치한다. 중앙 광장은 비운다.
- Inn: plaza 이후 남쪽 secondary lane. cart가 회전할 side yard와 fenced lodging yard를 둔다.

service building의 정체성은 서로 다른 전용 house mesh보다 frontage, yard depth, prop cluster, ground wear, lighting으로 구분한다.

## 8. Farm / Forest / Quarry Placement Plan

- Farm: Keep 남쪽의 완만한 물가 평지. 2~3개의 크기가 다른 밭, 휴경지, fence gap, cart turn area로 구성한다. crop row를 완벽히 평행하게 반복하지 않는다.
- Lumberyard: farm보다 북서쪽, main road와 forest 사이. 숲에서 나온 통나무가 마을로 들어가기 전 적재되는 위치다. clear-cut edge와 standing tree group의 경계가 보여야 한다.
- Forest: 오른쪽과 상단 화면 경계를 감싸되 균일한 tree grid를 사용하지 않는다. 5–9그루 cluster, 작은 clearing, 돌출된 lone tree를 반복한다.
- Quarry: 북동쪽 높은 rocky bank. `Stone_1~4`를 크기·회전·높이가 다른 outcrop으로 묶고, cart path가 작업면 아래를 따라 접근한다.
- Water: forest/quarry의 runoff가 Keep 옆 lake/stream으로 모여 farm 쪽으로 흐르는 형태다. 두 개의 crossing만 허용한다: Keep approach bridge와 production cart bridge.

## 9. Cuteskull / Quaternius 역할 분담

Cuteskull을 건물·성벽·시장·큰 수목·물·다리의 주 시각언어로 사용한다. 같은 texture family가 넓은 silhouette를 통일하므로 화면의 약 70–80%를 담당한다.

Quaternius는 Cuteskull에 없는 작은 의미 전달용 소품에만 사용한다: anvil, pickaxe, chopping block, crops, dead tree, bush, flower, torch, crate variation. Quaternius의 채도가 높은 붉은 foliage와 지나치게 깨끗한 props는 제한하고 scale/material tone을 Cuteskull에 맞춘다.

두 팩을 한 cluster 안에서 무작위로 섞지 않는다. 건물/대형 자연물은 Cuteskull, 기능 표식과 understory는 Quaternius라는 크기 계층을 유지한다.

## 10. 구현 시 제거해야 할 현재 Visual 문제

1. 긴 직선 성벽과 양 끝 tower가 레벨 경계선처럼 보이는 문제. gate 중심으로 길이를 줄이고 높이·끝처리를 비대칭화한다.
2. battlefield/corruption의 거대한 단색 polygon. 색 경계를 작은 terrain patch와 자연물로 분해한다.
3. main road가 여러 직사각형 띠의 거대한 교차로로 보이는 문제. 폭 변화와 curved edge가 있는 연속 표면으로 교체한다.
4. plaza가 완전한 원형 disc로 보이는 문제. 비대칭 stone pocket과 worn transition으로 변경한다.
5. Keep이 마을 중앙의 조립된 벽/탑 묶음처럼 보이는 문제. 물 건너 east bank의 fortified compound로 재구성한다.
6. 건물 입구 방향과 길의 관계가 약한 문제. 모든 주요 건물 frontage를 먼저 정하고 그 뒤 footprint를 배치한다.
7. 남쪽 주택이 열린 초록 평면에 흩어진 문제. 작은 lane, garden, fence gap, 공동 공간으로 cluster를 형성한다.
8. 시냇물이 일정 폭의 긴 직선 수로처럼 보이는 문제. lake pocket, 폭 변화, shoreline vegetation, 두 crossing으로 재구성한다.
9. orange roof와 red tree가 focal hierarchy를 빼앗는 문제. civilian roof와 foliage를 muted brown/slate/olive로 정리한다.
10. production props가 좌표에 놓인 작은 아이콘처럼 보이는 문제. ground wear, storage edge, working clearance를 포함한 yard 단위로 묶는다.
11. 화면 전체의 object scale과 asset-family 밀도가 제각각인 문제. camera는 유지하고, Cuteskull building을 기준 척도로 삼아 tree/prop/NPC scale을 재조정한다.
12. open space가 기능 없는 빈 ground로 남는 문제. 각 공터에 staging, grazing, garden, cart turning, firebreak 같은 한 가지 공간 목적을 부여한다.

구현 acceptance의 핵심은 asset 수가 아니라 시선 흐름이다. 기본 카메라에서 gate, main street, plaza, bridge, west-facing Keep entrance가 순서대로 읽히고, 그 축 바깥에서 주거·농업·생산이 자연스럽게 가지를 뻗어야 한다.
