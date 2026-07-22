' graphics-demo.bas -- a small animated QBJS graphics program.
' Demonstrates SCREEN, integer division (the "\" that needs the func_Abs fix),
' and a simple animation loop. Build with mode "auto".
'   qbjs-build.sh graphics-demo.bas --name "Bouncing Box"

Screen _NewImage(640, 480, 32)
_Title "QBJS Graphics Demo"

Dim x As Integer, y As Integer
Dim dx As Integer, dy As Integer
Dim boxSize As Integer

boxSize = 40
x = _Width \ 2      ' integer division -- exercises the headless compiler fix
y = _Height \ 2
dx = 3
dy = 2

Do
    Cls , _RGB32(0, 0, 40)

    ' Bounce off the edges
    x = x + dx
    y = y + dy
    If x < 0 Or x > _Width - boxSize Then dx = -dx
    If y < 0 Or y > _Height - boxSize Then dy = -dy

    Line (x, y)-(x + boxSize, y + boxSize), _RGB32(255, 220, 0), BF

    Dim caption As String
    caption = "QBJS running in the browser"
    Color _RGB32(120, 200, 255)
    _PrintString ((_Width - _PrintWidth(caption)) \ 2, 8), caption

    _Limit 60
    _Display
Loop Until _KeyDown(27)   ' Esc to quit

System
