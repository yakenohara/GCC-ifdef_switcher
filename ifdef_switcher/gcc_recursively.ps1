# <License>------------------------------------------------------------

#  Copyright (c) 2019 Shinnosuke Yakenohara

#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.

#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.

#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

# -----------------------------------------------------------</License>

# <User Settings>-----------------------------------------
$strarr_extentions = @(
    "`.c",
    "`.h"
)
# ----------------------------------------</User Settings>

#変数宣言
$opRec = "/r" #Recursive処理指定文字列
$opPau = "/p" #エラーがあった場合にpauseする事を指定する文字列
$pauseWhenErr = $FALSE  #エラーがあった場合にpauseするかどうか

$gccOptionFilename = "gcc_option.sh"

$total = 0
$scsOfTotal = 0
$errOfTotal = 0
$file = 0
$scsOfFile = 0
$errOfFile = 0
$dir = 0
$scsOfDir = 0

$paramCheckProcess = 0
$baseDir = ""
$destDir = ""

#Recursiveに処理するかどうかをチェック
$mxOfArgs = $Args.count
for ($idx = 0 ; $idx -lt $mxOfArgs ; $idx++){
    
    if ($Args[$idx] -eq $opPau){ #エラーがあった場合にpauseする事を指定する文字列の場合
        $pauseWhenErr = $TRUE
        $Args[$idx] = $null #処理対象から除外
    }
}

#処理対象リスト作成
$list = New-Object System.Collections.Generic.List[System.String]
$paramCheckProcess = 0
foreach ($arg in $args){
    
    if($arg -ne $null){ #処理対象から除外していなければ

        if ($paramCheckProcess -eq 0) { #source ディレクトリ指定の確認中

            $arg = (Resolve-Path $arg).Path
            $list.Add($arg)
            
            Get-ChildItem  -Recurse -Force -Path $arg | ForEach-Object {
                $list.Add($_.FullName)
            }
            
            $baseDir = $arg
            $paramCheckProcess = 1

        } elseif ($paramCheckProcess -eq 1) { #source ディレクトリ指定の確認中

            $destDir = $arg
            $paramCheckProcess = 2

        } else { # 引数チェック終了
            break
        }
    }
}

#パラメータ数チェック
if ($paramCheckProcess -eq 0){ #処理対象が指定されていない
    Write-Host "Argument not specified"
    $errOfTotal = 1
    
}else{ #処理対象が1つ以上ある

    if ($paramCheckProcess -eq 1) { #出力先ディレクトリ指定がない
        $destDir = $baseDir + "_prepro"
    }

    if (Test-Path $destDir -PathType Container){ # 出力先ディレクトリがすでに存在する場合
        Remove-Item -r -Force $destDir #削除
    }
    mkdir $destDir | Out-Null #作成
    $destDir = (Resolve-Path $destDir).Path

    # gcc オプションの配列化
    $gccOption = cat ( (Split-Path ( & { $myInvocation.ScriptName } ) -parent) + "\" + $gccOptionFilename)
    $gccOption = $gccOption -replace "`r`n","`n"
    $gccOption = $gccOption -replace "`r","`n"
    $gccOption = $gccOption -split "`n"

    $gccOptionOnCmd = New-Object System.Collections.Generic.List[System.String]

    #コメント削除
    $mxOfOption = $gccOption.count
    for ($idx = 0 ; $idx -lt $mxOfOption ; $idx++){
        $gccOption[$idx] = $gccOption[$idx] -replace " *#.*$", ""
        $gccOption[$idx] = $gccOption[$idx] -replace "^ +", ""
        $gccOption[$idx] = $gccOption[$idx] -replace " +$", ""
        
        if(!([string]::IsNullOrEmpty($gccOption[$idx]))){
            $gccOptionOnCmd.Add(($gccOption[$idx]))
        }
    }

    # $gccOptionOnCmd|foreach{
    #     echo $_
    # }
    # Read-Host "Press Enter key to continue..."

    #タイムスタンプ更新ループ
    foreach ($path in $list) {
        
        Write-Host $path
        
        if (Test-Path $path -PathType container){ #ディレクトリの場合
            
            $scsOfDir++
            $dir++
        
        } elseif (Test-Path $path -PathType leaf) { #ファイルの場合

            $destPath = $path.Replace($baseDir, $destDir)
            $destParentPath = Split-Path -Parent $destPath

            if (-Not(Test-Path ($destParentPath) -PathType container)){ #ディレクトリが存在しない場合
                
                try{
                
                    New-Item -Itemtype Directory $destParentPath -ErrorAction stop | Out-Null
                    # `New-Item`実行時にアクセスエラーが発生した場合は、catch出来ないので、 ` -ErrorAction stop` する
                    # アクセスエラーが発生しない場合に表示されるls結果は不要な為、` | Out-Null` する
    
                } catch { #アクセスエラーが発生した場合
                    Write-Error $Error[0]
                }
            }

            $str_ext = [System.IO.Path]::GetExtension($path);

            $bool_in_list = $FALSE # 処理対象拡張子リストに存在するかどうか
            foreach ($str_extention in $strarr_extentions){
                if ( $str_ext -eq $str_extention ){ # 処理対象拡張子リストに存在する場合
                    $bool_in_list = $TRUE
                    break
                }
            }

            if ($bool_in_list) { # ソースコードの場合
                gcc $gccOptionOnCmd $path -o $destPath # プリプロセスのみ実行
                if($LASTEXITCODE -eq 0){ #コンパイルエラーなしの場合
                    $scsOfFile++
                } else {
                    $errOfFile++
                }
            
            }else{ # ソースコードではない場合
                Copy-Item $path $destPath
                $scsOfFile++
            }

            $file++
        
        } else { #存在しないパスの場合

            Write-Error "Unkown path"
        }
    }

    #結果集計
    $total = $file + $dir
    $scsOfTotal = $scsOfFile + $scsOfDir
    $errOfTotal = $errOfFile

    #結果表示
    Write-Host ""
    Write-Host "Number of failed files:"
    Write-Host $errOfFile

}

#失敗処理がある場合はpauseする
if (($errOfTotal -gt 0) -And ($pauseWhenErr)){
    Write-Host ""
    Read-Host "Press Enter key to continue..."
    
}

if ($errOfTotal -gt 0) { #エラーが発生した場合
    exit 1
} else{ #エラーがなかった場合
    exit 0
}
