import raylib, rayutils, sequtils, lenientops, sugar, random, algorithm

const
    screenWidth = 1920
    screenHeight = 1080
    marginX = 200
    marginY = 100

InitWindow screenWidth, screenHeight, "Frontlines"
SetTargetFPS 60

randomize()

var
   gridX = 12
   gridY = 8
   grid = newSeqWith(gridX * gridY, (CLEAR, 1, 0))
   cellsize = makevec2((screenWidth - 2 * marginX) div gridX, (screenHeight - 2 * marginY) div gridY)
   held = -1
   dest = -1
   turn = 0 # {Red, Yellow, Blue, Green} -> {0, 1, 2, 3}
   tcFrac : float
   turnCounter = 1
   checkedTc : bool
   turnCols = [RED, YELLOW, SKYBLUE, GREEN]
   phase = 0 # {Deploy, Attack, Distribute} -> {0. 1. 2}
   mvcount : int
   mousedCell : int
   numTroops = [0, 0, 0, 0]
   heldCells = [0, 0, 0, 0]
   ruleset = 1

func gFlatten(v : Vector2, gridX : int) : int = 
    v.x.int + v.y.int * gridX

func drawGridlines[T](grid : seq[T], posX, posY : int, cs: Vector2, gridX, gridY, held: int, col : Color) =
    for i in 0..<gridX:
        for j in 0..<gridY:
            if gFlatten(makevec2(i, j), gridX) == held: 
                DrawRectangleLines(posX + int cs.x * i, posY + int cs.y * j, int cs.x, int cs.y, WHITE)
            elif grid[gFlatten(makevec2(i, j), gridX)][0] == CLEAR:
                DrawRectangleLines(posX + int cs.x * i, posY + int cs.y * j, int cs.x, int cs.y, col)


func drawCells(grid : seq[(Color, int, int)], posX, posY : int, cs : Vector2, gridX, gridY : int, turnCols : array[4, Color]) =
    for i in 0..<grid.len:
        if grid[i][0] in turnCols:
            let pos = makevec2((i mod gridX) * cs.x + posX, (i div gridX) * cs.y + posY)
            DrawRectangleV(pos, cs, grid[i][0])
            drawTextCentered($grid[i][1], pos.x.int + cs.x.int div 2, pos.y.int + cs.y.int div 2, int(int(cs.x + cs.y) / 5.15), AGREY)

func screenToArr(v : Vector2, marginX, marginY, gridX, gridY : int, cs : Vector2) : int =
    let v = v - makevec2(marginX, marginY)
    let grid = (v div cs) - 1
    if grid.x.int notin 0..<gridX or grid.y.int notin 0..<gridY:
        return -1
    return gFlatten(grid, gridX) 

func getNeighbors(grid : seq[(Color, int, int)], gridX, inx : int, turnCols : array[4, Color]) : seq[(Color, int, int)] =
    if inx > 0 and (inx - 1) div gridX == inx div gridX and grid[inx - 1][0] in turnCols:
        result.add grid[inx - 1]
    if inx < grid.len - 1 and (inx + 1) div gridX == inx div gridX and grid[inx + 1][0] in turnCols:
        result.add grid[inx + 1]
    if inx + gridX <= grid.len - 1 and grid[inx + gridX][0] in turnCols:
        result.add grid[inx + gridX]
    if inx - gridX >= 0 and grid[inx - gridX][0] in turnCols:
        result.add grid[inx - gridX]

func rawGetNeighborsIndices(grid : seq[(Color, int, int)], gridX, inx : int, turnCols : array[4, Color]) : seq[int] =
    if inx > 0 and (inx - 1) div gridX == inx div gridX:
        result.add inx - 1
    if inx < grid.len - 1 and (inx + 1) div gridX == inx div gridX:
        result.add inx + 1
    if inx + gridX <= grid.len - 1:
        result.add inx + gridX
    if inx - gridX >= 0:
        result.add inx - gridX   

func getNeighborsIndices(grid : seq[(Color, int, int)], gridX, inx : int, turnCols : array[4, Color]) : seq[int] =
    if inx > 0 and (inx - 1) div gridX == inx div gridX and grid[inx - 1][0] in turnCols:
        result.add inx - 1
    if inx < grid.len - 1 and (inx + 1) div gridX == inx div gridX and grid[inx + 1][0] in turnCols:
        result.add inx + 1
    if inx + gridX <= grid.len - 1 and grid[inx + gridX][0] in turnCols:
        result.add inx + gridX
    if inx - gridX >= 0 and grid[inx - gridX][0] in turnCols:
        result.add inx - gridX

func getPossibleMoves[T](grid : seq[T], gridX : int, col : Color, turnCols : array[4, Color]) : seq[(int, int)] =
    let ctrled = toSeq findAll(grid, x => x[0] == col)
    for i in ctrled:
        if grid[i][1] > 1:
            for j in getNeighborsIndices(grid, gridx, i, turnCols):
                if grid[j][0] != col:
                    result.add (i, j)

func colToInt(col : Color) : int =
    if col == RED: return 0
    elif col == YELLOW: return 1
    elif col == GREEN: return 2
    elif col  == SKYBLUE: return 3

func findUnitNums[T](grid : seq[T]) : array[4, int] =
    for i in grid:
        if i[0] == RED:
            result[0] += i[1]
        elif i[0] == YELLOW:
            result[1] += i[1]
        elif i[0] == SKYBLUE:
            result[2] += i[1]
        elif i[0] == GREEN:
            result[3] += i[1]

func findControlledCells[T](grid : seq[T]) : array[4, int] =
    let x = @[toSeq findAll(grid, x => x[0] == RED), toSeq findAll(grid, x => x[0] == YELLOW), toSeq findAll(grid, x => x[0] == SKYBLUE), toSeq findAll(grid, x => x[0] == GREEN)]
    return [x[0].len, x[1].len, x[2].len, x[3].len]

func incTurn(turn : int, nTroops : openArray[int]) : int =
    result = turn + 1; result = result mod 4
    while nTroops[result] == 0: result += 1; result = result mod 4

proc randomizeGrid(grid : seq[(Color, int, int)], gridX, gridY : int, turnCols : array[4, Color]) : seq[(Color, int, int)] =
    result = newSeqWith(gridX * gridY, (AGREY, 0, 0))
    let nTiles = gridX * gridY - gridX * 2 + rand(gridX)
    let center = (gridY div 2) * gridX + gridX div 2
    echo center
    var filledCells = @[center]
    for i in 0..<nTiles:
        var currentCell = center
        while currentCell in filledCells:
            let nbors = rawGetNeighborsIndices(grid, gridX, currentCell, turnCols)
            echo nbors
            currentCell = nbors[rand(nbors.len - 1)]
        echo currentCell
        filledCells.add currentCell
        let nColsCount = [result.filterIt(it[0] == turnCols[0]).mapIt(it[1]), result.filterIt(it[0] == turnCols[1]).mapIt(it[1]), result.filterIt(it[0] == turnCols[2]).mapIt(it[1]), result.filterIt(it[0] == turnCols[3]).mapIt(it[1])]
        var nCols = newSeqWith(4, 0)
        for i in 0..<4:
            if nColsCount[i] != @[]: nCols[i] = nColsCount[i].foldl(a + b)
        let col = nCols.find(nCols.sorted(Ascending)[0])
        result[currentCell] = (turnCols[col], rand(3) + 1, 0)


func getTcFrac(turn : int, nTroops : array[4, int]) : float =
    let nAlive = toSeq(nTroops.findAll(x => x > 0)).len
    let nInxDead = toSeq nTroops.findAll(x => x <= 0)
    result = turn + 1f
    for i in nInxDead:
        if turn > i:
            result += -1
    result = result / nAlive

grid = randomizeGrid(grid, gridX, gridY, turnCols)


#[
    Mechanics overview

    - Grid/map of points, 6x10
    - Attacking empty point loses 0 units
    - 1 unit per occupied tile
    - Attacking defended tile loses #troopsInTile for both sides
        - If #attackers > #defenders, #defenders += -#defenders and #attackers += -#defenders
        - If #attackers == #defenders, #attackers = 1, #defenders = 1
        - If #defenders > #attackers, #attackers += -#defenders and #attackers = 1
]#

while not WindowShouldClose():
    ClearBackground BGREY

    if turncounter mod 10 == 0 and not checkedTc:
        ruleset = 1
        checkedTc = true
    elif turncounter mod 10 != 0:
        ruleset = 0
        checkedTc = false

    if IsMouseButtonPressed(MOUSE_LEFT_BUTTON):
        mousedCell = screenToArr(GetMousePosition(), marginX, marginY, gridX, gridY, cellsize)
    else: mousedCell = -1
    numTroops = findUnitNums grid
    heldCells = findControlledCells grid

    # Deploy Phase 

    if phase == 0:
        for i in 0..<grid.len:
            if grid[i][0] == turnCols[turn]:
                var nbors = getNeighbors(grid, gridX, i, turnCols).filterIt(it[0] == turnCols[turn]).len
                if ruleset == 0:
                    grid[i] = (grid[i][0], grid[i][1] + getNeighbors(grid, gridX, i, turnCols).len - nbors, grid[i][2])
                elif ruleset == 1:
                    grid[i] = (grid[i][0], grid[i][1] + getNeighbors(grid, gridX, i, turnCols).len - nbors, grid[i][2])
        phase = 1

    # Attack Phase

    if mousedCell != -1:
        if held == mousedCell:
            held = -1
        if grid[mousedCell][0] == turncols[turn] and grid[mousedCell][1] > 1:
            held = mousedCell
        elif held != -1 and grid[mousedCell][0] != turnCols[turn]:
            if mousedCell notin getNeighborsIndices(grid, gridX, held, turnCols):
                held = -1
            else: dest = mousedCell
    
    if held != -1 and dest != -1 and grid[dest][0] in turnCols:
        if grid[held][1] > grid[dest][1]:
            grid[dest] = (turnCols[turn], max(1, grid[held][1] - grid[dest][1]), grid[held][2])
        else:
            grid[dest] = (grid[dest][0], max(1, grid[dest][1] - grid[held][1]), grid[dest][2])
        grid[held] = (turnCols[turn], 1, grid[held][2])
        held = -1
        dest = -1
    elif held == -1 and dest == -1 and (IsKeyPressed(KEY_SPACE) or turn != 0):
        phase = 0
        mvcount = 0
        turn = incTurn(turn, numTroops)
        let nAlive = numTroops.filterIt(it > 0).len
        if nAlive > 1: tcFrac = getTcFrac(turn, numTroops)
        if tcFrac.int.float == tcFrac:
            turnCounter += tcFrac.int
            tcFrac = 0

    ## AI Agent ##

    if turn != 0:
        let mvfactor = max(0.001, heldCells[turn] * -0.005 + 6.5)
        if rand(100) < mvcount * mvfactor:
            held = -1; dest = -1
            mvcount = int.high
        else:
            var moves = getPossibleMoves(grid, gridX, turnCols[turn], turnCols)
            if moves.len == 0:
                mvcount = int.high
            else:
                var movesWt : seq[(int, int)]
                movesWt &= moves.filterIt(grid[it[0]][1] >= grid[it[1]][1]) & moves.filterIt(grid[it[0]][1] >= grid[it[1]][1]) # 3x chance to play move if more Attackers
                movesWt &= moves.filterIt(numTroops[colToInt grid[it[0]][0]] > numTroops[colToInt grid[it[1]][0]]) # 2x chance to play move if more total troops (ensure more eliminations)
                movesWt &= moves.filterIt(grid[it[0]][1] >= grid[it[1]][1]).filterIt(it in moves.filterIt(numTroops[colToInt grid[it[0]][0]] > numTroops[colToInt grid[it[1]][0]])) # 2x chance to play if both of the above are true
                # if ruleset == 0:
                #     movesWt &= moves.filterIt(getNeighbors(grid, gridX, it[0]).filter(x => x[0] == turnCols[turn]).len < getNeighbors(grid, gridX, it[1]).filter(x => # x[0] == turnCols[turn]).len) ## 2x chance to play move if less neighbors
                # elif ruleset == 1:
                #     movesWt &= moves.filterIt(getNeighbors(grid, gridX, it[0]).filter(x => x[0] == turnCols[turn]).len > getNeighbors(grid, gridX, it[1]).filter(x => # x[0] == turnCols[turn]).len) ## 2x chance to play move if more neighbors 
                moves &= movesWt

                (held, dest) = moves[rand(moves.len - 1)]
                mvcount += 1


    BeginDrawing()

    drawCells(grid, marginX, marginY, cellsize, gridX, gridY, turnCols)
    drawGridlines(grid, marginX, marginY, cellsize, gridX, gridY, held, makecolor(50, 50, 50))
    if turn == 0:
        drawTextCentered("RED's turn!", screenWidth div 2, 45, 50, turnCols[turn])
    if turn == 1:
        drawTextCentered("YELLOW's turn!", screenWidth div 2, 45, 50, turnCols[turn])
    if turn == 2:
        drawTextCentered("BLUE's turn!", screenWidth div 2, 45, 50, turnCols[turn])
    if turn == 3:
        drawTextCentered("GREEN's turn!", screenWidth div 2, 45, 50, turnCols[turn])
    drawTextCentered($numTroops & " " & $ruleset & " " & $turnCounter, screenWidth div 2, screenHeight - 45, 30, turnCols[turn])
    EndDrawing()

CloseWindow()