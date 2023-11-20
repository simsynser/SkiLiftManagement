;this model is to simulate waiting time of skiers in a skiresort.
;it was created for a skiresort with two lifts (six chairs each) but
;can be expanded as required

;autor: Alina Heinrich
;date: 2021-2022


extensions [ gis time]

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~DEFINE GLOBAR VARIABLE FOR ALL AGENTS~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

globals [
  liftaxis-dataset
  slope-dataset
  slope-layer-dataset
  currenttime
  endtime
  resettime   ;after this time monitoring begins
  s-per-tick   ;seconds per tick
  m-per-patch   ;meter per patch
  valley-stations   ;list of all valley stations
  total-waiting-ticks
  total-skiing-ticks
  rides
  lift-capacities
  ratio
]

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~~~~~~~~~~CREATE AGENTSETS~~~~~~~~~~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

breed [liftnodes liftnode]
breed [slopenodes slopenode]
breed [skiers skier]
breed [forests forest]

liftnodes-own [
  waiting-list   ;list with waiting skiers
  lift-capacity
]

slopenodes-own [
  start-node?
]

skiers-own [
  target   ;skier moves to
  speed   ;current speed in m/sec
  ski-speed   ;down the slope

  status ;inserted as new observer variable by CN

]

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~~~~~~~~~~PROCEDURE STEPS~~~~~~~~~~~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

to set-up
  clear-all
  setup-globals

  ask patches [set pcolor white]
  ;~~load geo data
  set liftaxis-dataset gis:load-dataset "GeoDaten/axiss.shp"
  set slope-dataset gis:load-dataset "GeoDaten/slopelines.shp"
  set slope-layer-dataset gis:load-dataset "GeoDaten/Pisten.shp"   ;for slopes presentation only
  let env (gis:envelope-union-of(gis:envelope-of liftaxis-dataset)
                                      gis:envelope-of slope-dataset)
  gis:set-transformation env (list (min-pxcor + 4) (max-pxcor - 4) (min-pycor + 4) (max-pycor - 4))
  ask patches gis:intersecting slope-layer-dataset  [
    set pcolor blue + 4
  ]
  ;~~
  ;~~create forest
  create-forests 350
  [
    setxy random-pxcor random-pycor
;    while [pcolor != white]
    while [any? patches with [pcolor != white] in-radius 6]
    [
      setxy random-pxcor random-pycor
    ]
    set shape "tree"
    set color green + 4
    set size 10
  ]
  ;~~

  ;~~convert patches in meter
  let extend-in-m item 1 gis:world-envelope - item 0 gis:world-envelope   ;how wide is the world in meter
  let extend-in-p max-pxcor - min-pxcor   ;how wide is the world in patches
  set m-per-patch extend-in-m / extend-in-p
  ;~~

  create-liftnetwork
  create-slopenetwork

  ;create user defined number of skiers
  create-skiers num-skiers [
    setup-skier
  ]
  ;~~

  reset-ticks
end

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~DEFINE VALUES FOR GLOBAL VARIABLES~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

to setup-globals
  set currenttime time:create "2000/01/01 0:00"
  set endtime time:create "2000/01/01 1:20"
  set resettime time:create "2000/01/01 0:20"
  set s-per-tick 0.1
  set valley-stations []
  set rides 0   ;value null causes "divide by zero"  error at beginning of simulation
  set lift-capacities list 2362 2400
end

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~CREATE NETWORK FROM LIFTDATA~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

to create-liftnetwork
  foreach gis:feature-list-of liftaxis-dataset [   ;loop over the list of lifts (each is a polyline)
    liftfeature ->
    let nodelist []
    let previous-node nobody
    foreach gis:vertex-lists-of liftfeature [   ;loop over the list of each segment/pair of coordinates
      liftsegment ->
      foreach liftsegment [   ;loop over the list of vertices
        liftvertex -> let location gis:location-of liftvertex
        create-liftnodes 1 [   ;create 1 node at location of the vertex
          set xcor item 0 location
          set ycor item 1 location
          set nodelist lput liftnode who nodelist
          set hidden? true
          ifelse previous-node = nobody [
          ][
              create-link-to previous-node   ;create link between nodes
          ]
          set previous-node self
        ]
      ]
      ask previous-node [
        set waiting-list []   ;set waiting list on the last node, which is the valley station
        set valley-stations lput self valley-stations   ;add valley station to list of all valley stations (for plotting)
        set lift-capacity first lift-capacities   ;save first value of capacities list
        set lift-capacities but-first lift-capacities   ;delete first value from capacities list
      ]
    ]
    ask links [set color blue]
  ]
end

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~CREATE NETWORK FROM SLOPEDATA~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

to create-slopenetwork
  foreach gis:feature-list-of slope-dataset [
    slopefeature ->
    let previous-node nobody
    foreach gis:vertex-lists-of slopefeature [
      slopesegment ->
      foreach slopesegment [
        slopevertex -> let location gis:location-of slopevertex
        create-slopenodes 1 [
          set xcor item 0 location
          set ycor item 1 location
          set hidden? true
          ifelse previous-node = nobody [
            set start-node? true
          ][
            create-link-from previous-node [hide-link]
          ]
          set previous-node self
        ]
      ]
    ]
  ]
end

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~~~~~~PROCEDURE TO SETUP SKIER~~~~~~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

to setup-skier
  set shape "skier"
  set size 5
  set target one-of slopenodes   ;slopenode is a target to move to for skier
  move-to target
  set ski-speed abs random-normal 4.4 2   ;skier moves with the speed 4.4m/s with 2m/s stand. dev.
  set speed ski-speed
end
;~~

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~~~~~PROCEDURE TO RUN THE MODEL~~~~~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

to go
  ;~~ set time of the model. It runs one hour and 30min.
  ;first 30 min are to setup the model, after 30 min monitoring begins
  set currenttime time:plus currenttime s-per-tick "seconds"

  if time:is-equal? currenttime resettime  ;was commented out in original model, probably commented out by Alina to see full output
  [
    set total-waiting-ticks 0
    set rides 0
    clear-all-plots
  ]

  if time:is-after? currenttime endtime
  [stop]
  ;~~

  phase-lift
  move-skier

  ifelse count skiers with [status = "in lift"] > 0
           [set ratio count skiers with [status = "on slope"] / count skiers with [status = "in lift"]]
           [set ratio 0]


  tick
end

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~~~~~~PROCEDURE TO MOVE SKIERS~~~~~~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

to move-skier
  ask skiers [
    let current_node_type [breed] of target
    if distance target < speed / m-per-patch * s-per-tick [  ; when the skier gets close to their target
      set target one-of [out-link-neighbors] of target  ; choose a new target
    ]

    if target = nobody [  ; if the skier is at the end of the lift or slope
      if current_node_type = slopenodes [  ; if the skier is at the end of slope
        set status "on slope"
        set target one-of liftnodes in-radius 5  ; choose a random lift near the skier
        ask target [
          set waiting-list lput myself waiting-list  ; and put skier on the waiting list of the lift
        ]
        set speed 0

      ]

      if current_node_type = liftnodes [  ; if the skier is at the end of the lift
        set status "in lift"
        set target one-of slopenodes in-radius 5 with [start-node? = true]  ; choose a random slope near the skier
        set speed ski-speed
        set shape "skier"
        set color one-of base-colors
      ]
    ]
    if speed = ski-speed [
      set total-skiing-ticks total-skiing-ticks + 1
    ]
    face target
    forward speed / m-per-patch * s-per-tick
  ]
end

;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
;~~~~~~~PROCEDURE TO RIDE THE LIFT~~~~~~
;~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

to phase-lift
;  ask liftnodes with [waiting-list != 0] [
  ask turtle-set valley-stations [   ;loop over all valley stations
    set total-waiting-ticks total-waiting-ticks + length waiting-list   ;increase total waiting ticks by number of waiting skiers
    let current-lift-capacity lift-capacity * lift-speed / 5   ;if lift speed is higher or lower than standart 5m/s, scale lift capacity accordingly
    let chair-capacity 6   ;this model represents 6 seats per gondola
    let chair-period int(chair-capacity / ( current-lift-capacity / 60 / 60 ) / s-per-tick)   ;calculate every how many ticks a gondola leaves the station
    if ticks mod chair-period = 0 [   ;this is true if it is time for a gondola to leave the station
      repeat chair-capacity [
        if not empty? waiting-list [   ;check if someone is in the waiting list
          ;tell the skier to proceed as a gondola
          ask first waiting-list [
            set speed lift-speed
            set rides rides + 1
            set shape "pentagon"
            set color black
          ]
          set waiting-list butfirst waiting-list   ;delete that skier from the waiting list
        ]
      ]
    ]
  ]
end
@#$#@#$#@
GRAPHICS-WINDOW
237
10
1287
561
-1
-1
2.0
1
10
1
1
1
0
0
0
1
-260
260
-135
135
0
0
1
ticks
30.0

BUTTON
236
601
308
634
NIL
set-up
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
503
571
675
604
num-skiers
num-skiers
100
3000
150.0
50
1
NIL
HORIZONTAL

BUTTON
319
601
382
634
NIL
go\n
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
1293
79
1634
199
total-waiting-time in min
ticks
min
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-waiting-ticks * s-per-tick / 60"

MONITOR
812
628
1021
673
average waiting time per ride in min
total-waiting-ticks / rides * s-per-tick / 60
2
1
11

PLOT
1291
417
1632
560
num of waiting skiers
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot count skiers with [ speed = 0 ]"
"pen-1" 1.0 0 -7500403 true "" "plot [length waiting-list] of item 0 valley-stations"
"pen-2" 1.0 0 -2674135 true "" "plot [length waiting-list] of item 1 valley-stations"

MONITOR
1052
690
1184
735
num of waiting skiers
count skiers with [ speed = 0 ]
17
1
11

CHOOSER
537
621
675
666
lift-speed
lift-speed
1 2 3 3.5 4 4.5 5
2

MONITOR
1293
11
1350
56
clock
time:show currenttime \"HH:mm:ss\"
17
1
11

PLOT
1292
248
1634
368
average waiting time in min
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot total-waiting-ticks / rides * s-per-tick / 60"

MONITOR
780
571
1022
616
total average waiting time per skier in min
( total-waiting-ticks * s-per-tick / 60 ) / num-skiers
2
1
11

MONITOR
889
689
1020
734
total skiing time in min
total-skiing-ticks  * s-per-tick / 60
2
1
11

MONITOR
1051
631
1220
676
total average rides per skier
rides / num-skiers
17
1
11

MONITOR
1050
570
1282
615
total average skiing time per skier in min
( total-skiing-ticks  * s-per-tick / 60 ) / num-skiers
2
1
11

PLOT
21
410
221
560
Slope Lift Ratio
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot ratio"

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120
Rectangle -1 true false 75 120 225 180

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

skier
false
0
Circle -7500403 true true 120 30 60
Polygon -7500403 true true 120 90 120 195 90 255 75 285 90 300 135 225 150 300 180 300 165 285 165 195 180 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 180 90 225 150 210 165 150 105
Polygon -7500403 true true 120 90 75 165 90 180 150 105
Line -7500403 true 225 150 225 285
Line -7500403 true 75 165 45 180
Line -7500403 true 15 300 240 300

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

test
true
1
Circle -1 false false 177 87 66
Rectangle -7500403 false false 180 90 180 165
Polygon -1 false false 180 180 240 210 225 225 150 180 180 180 180 180
Polygon -1 false false 180 105 180 180 150 180 150 135 105 120 105 165 60 195 45 195 45 180 75 150 75 105 105 75 150 90
Line -1 false 240 255 15 195
Line -1 false 240 255 255 255

tree
false
7
Circle -14835848 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -14835848 true true 65 21 108
Circle -14835848 true true 116 41 127
Circle -14835848 true true 45 90 120
Circle -14835848 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.2.2
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
<experiments>
  <experiment name="experiment0" repetitions="1" runMetricsEveryStep="true">
    <setup>set-up</setup>
    <go>go</go>
    <metric>total-waiting-ticks / rides * s-per-tick / 60</metric>
    <enumeratedValueSet variable="num-skiers">
      <value value="1000"/>
      <value value="2000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="lift-speed">
      <value value="4"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="test reset time" repetitions="1" runMetricsEveryStep="false">
    <setup>set-up</setup>
    <go>go</go>
    <metric>( total-waiting-ticks * s-per-tick / 60 ) / num-skiers</metric>
    <metric>rides / num-skiers</metric>
    <metric>total-waiting-ticks / rides * s-per-tick / 60</metric>
    <metric>( total-skiing-ticks  * s-per-tick / 60 ) / num-skiers</metric>
    <steppedValueSet variable="num-skiers" first="1000" step="100" last="3000"/>
    <steppedValueSet variable="lift-speed" first="3" step="0.5" last="5"/>
  </experiment>
  <experiment name="resetTimeExtreme" repetitions="100" runMetricsEveryStep="true">
    <setup>set-up</setup>
    <go>go</go>
    <metric>count skiers with [ speed = 0 ]</metric>
    <metric>[length waiting-list] of item 0 valley-stations</metric>
    <metric>[length waiting-list] of item 1 valley-stations</metric>
    <enumeratedValueSet variable="num-skiers">
      <value value="1000"/>
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="lift-speed">
      <value value="3"/>
      <value value="5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="szenarios100to3000" repetitions="1" runMetricsEveryStep="false">
    <setup>set-up</setup>
    <go>go</go>
    <metric>( total-waiting-ticks * s-per-tick / 60 ) / num-skiers</metric>
    <metric>rides / num-skiers</metric>
    <metric>total-waiting-ticks / rides * s-per-tick / 60</metric>
    <metric>( total-skiing-ticks  * s-per-tick / 60 ) / num-skiers</metric>
    <steppedValueSet variable="num-skiers" first="100" step="100" last="3000"/>
    <steppedValueSet variable="lift-speed" first="3" step="0.5" last="5"/>
  </experiment>
  <experiment name="resetTimeExtreme100runs" repetitions="100" runMetricsEveryStep="true">
    <setup>set-up</setup>
    <go>go</go>
    <metric>count skiers with [ speed = 0 ]</metric>
    <enumeratedValueSet variable="num-skiers">
      <value value="1000"/>
      <value value="3000"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="lift-speed">
      <value value="3"/>
      <value value="5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment" repetitions="1" runMetricsEveryStep="true">
    <setup>setup</setup>
    <go>go</go>
    <metric>count turtles</metric>
    <enumeratedValueSet variable="num-skiers">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="lift-speed">
      <value value="5"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="lift speed on ratio" repetitions="10" runMetricsEveryStep="true">
    <setup>set-up</setup>
    <go>go</go>
    <metric>ratio</metric>
    <enumeratedValueSet variable="lift-speed">
      <value value="3"/>
      <value value="4"/>
      <value value="5"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
