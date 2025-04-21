#NoEnv
#SingleInstance Force
SetBatchLines, -1
SetMouseDelay, -1
CoordMode, Mouse, Screen

; 変数初期化
global info := {}
global hHook := 0
global lockDirection := ""
global startX := 0
global startY := 0
global moveThreshold := 4
global isProcessing := false  ; 再帰的な処理を防ぐフラグ
global timerRunning := false  ; タイマーが実行中かどうかのフラグ

; 終了時にフックを確実に解除
OnExit("CleanupHook")

; Ctrl+Pで強制終了
^p::ExitApp


; Shiftキーを押した時のイベント
~Shift::
    ; アクティブウィンドウがCLIP STUDIOかチェック
    if IsClipStudio() {
        ; CLIPスタジオの場合だけタイマー開始
        if (!timerRunning) {
            SetTimer, CheckMouseState, 10  
            timerRunning := true
        }
    }
    return

; Shiftキーを離した時のイベント
~Shift Up::
    ; フックを解除
    RemoveHook()
    ; タイマーを停止
    if (timerRunning) {
        SetTimer, CheckMouseState, Off
        timerRunning := false
    }
    ; 方向ロックをリセット
    lockDirection := ""
    return

; CLIP STUDIOかどうかをチェックする関数
IsClipStudio() {
    WinGetActiveTitle, activeTitle
    WinGet, activeProcess, ProcessName, A
    
    ; CLIP STUDIOのウィンドウタイトルやプロセス名をチェック
    return (InStr(activeTitle, "CLIP STUDIO") || InStr(activeProcess, "CLIPStudioPaint.exe") || InStr(activeProcess, "CLIPStudio.exe"))
}

; マウスの状態をチェック
CheckMouseState:
    ; アクティブウィンドウがCLIP STUDIOでない場合はフックを解除
    if (!IsClipStudio()) {
        RemoveHook()
        lockDirection := ""
        return
    }
    
    ; 処理中なら何もしない
    if (isProcessing)
        return
        
    isProcessing := true
    
    ; 左ボタンが押されているか確認
    if GetKeyState("LButton", "P") {
        ; 現在のマウス位置を取得
        MouseGetPos, currentX, currentY
        
        ; 左ボタンが押されている場合、方向を判定してロック
        if (hHook = 0) {
            ; 開始位置を記録
            startX := currentX
            startY := currentY
            
            ; まだ方向が決まっていないので、動きを見て判断する
            lockDirection := ""
            
            ; フックを設定
            info.startX := startX
            info.startY := startY
            info.direction := lockDirection
            hHook := SetMouseHook(info)
        } else {
            ; 方向が決まっていない場合のみ判定を行う
            if (lockDirection = "") {
                ; 累積移動量を計算
                totalDeltaX := Abs(currentX - startX)
                totalDeltaY := Abs(currentY - startY)
                
                ; 方向判定（十分な移動がある場合のみ）
                if (totalDeltaX > moveThreshold || totalDeltaY > moveThreshold) {
                    if (totalDeltaX > totalDeltaY) {
                        lockDirection := "Y" ; Y座標を固定
                        info.fixedY := currentY
                    } else {
                        lockDirection := "X" ; X座標を固定
                        info.fixedX := currentX
                    }
                    
                    ; 方向が決まったらフック情報を更新
                    info.direction := lockDirection
                }
            }
        }
    } else {
        ; 左ボタンが押されていない場合、フックを解除
        RemoveHook()
        lockDirection := ""
    }
    
    isProcessing := false
    return

; フックを解除する関数
RemoveHook() {
    global hHook
    if (hHook != 0) {
        DllCall("UnhookWindowsHookEx", "Ptr", hHook)
        hHook := 0
    }
}

; アプリ終了時のクリーンアップ
CleanupHook() {
    global hHook
    if (hHook != 0) {
        DllCall("UnhookWindowsHookEx", "Ptr", hHook)
        hHook := 0
    }
}

; マウスフックを設定する関数
SetMouseHook(info) {
    ; オブジェクトポインタを取得
    pInfo := Object(info)
    
    ; 低レベルマウスフックを設定
    newHook := DllCall("SetWindowsHookEx"
        , "Int", 14  ; WH_MOUSE_LL = 14
        , "Ptr", RegisterCallback("LowLevelMouseProc", "Fast", 3, pInfo)
        , "Ptr", DllCall("GetModuleHandle", "UInt", 0, "Ptr")
        , "UInt", 0
        , "Ptr")
    
    ObjRelease(pInfo)
    Return newHook
}

; 低レベルマウスプロシージャ
LowLevelMouseProc(nCode, wParam, lParam) {
    static WM_MOUSEMOVE := 0x200
    static lastProcessedX := 0
    static lastProcessedY := 0
    static processingMove := false
    
    ; CLIP STUDIOでない場合は処理しない
    if (!IsClipStudio())
        Return DllCall("CallNextHookEx", "UInt", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam)
    
    ; 既に処理中なら何もしない（無限ループ防止）
    if (processingMove)
        Return DllCall("CallNextHookEx", "UInt", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam)
    
    ; マウス移動以外のイベントは通常通り処理
    if (wParam != WM_MOUSEMOVE)
        Return DllCall("CallNextHookEx", "UInt", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam)
    
    ; 現在のカーソル位置を取得
    currentX := NumGet(lParam+0, "UInt")
    currentY := NumGet(lParam+4, "UInt")
    
    ; 前回処理した位置と同じなら処理しない（無限ループ防止）
    if (currentX = lastProcessedX && currentY = lastProcessedY)
        Return DllCall("CallNextHookEx", "UInt", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam)
    
    ; 保存したオブジェクト情報を取得
    info := Object(A_EventInfo)
    
    ; まだ方向が決まっていない場合は何もしない
    if (!info.HasKey("direction") || info.direction = "") {
        Return DllCall("CallNextHookEx", "UInt", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam)
    }
    
    ; 処理中フラグを設定
    processingMove := true
    
    ; 方向に応じてロック
    if (info.direction = "X") {
        ; X軸ロック（X座標を固定）
        if (info.HasKey("fixedX")) {
            lastProcessedX := info.fixedX
            lastProcessedY := currentY
            MouseMove, info.fixedX, currentY, 0
        }
    } else if (info.direction = "Y") {
        ; Y軸ロック（Y座標を固定）
        if (info.HasKey("fixedY")) {
            lastProcessedX := currentX
            lastProcessedY := info.fixedY
            MouseMove, currentX, info.fixedY, 0
        }
    }
    
    ; 処理中フラグを解除
    processingMove := false
    
    ; イベントを処理済みとしてマーク
    Return 1
}