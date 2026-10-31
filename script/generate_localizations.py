#!/usr/bin/env python3
"""Write the source catalogs. Keep all supported translations together."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = {
    "The export folder could not be saved. Choose another folder.": ("无法保存导出目录，请选择其他文件夹。", "書き出し先を保存できません。別のフォルダを選択してください。", "내보내기 폴더를 저장할 수 없습니다. 다른 폴더를 선택하세요."),
    "Play": ("播放", "再生", "재생"),
    "Pause": ("暂停", "一時停止", "일시 정지"),
    "Mute": ("静音", "消音", "음소거"),
    "Unmute": ("取消静音", "消音解除", "음소거 해제"),
    "Playback position": ("播放位置", "再生位置", "재생 위치"),
    "Playback time": ("播放时间", "再生時間", "재생 시간"),
    "Playback unavailable": ("无法播放", "再生できません", "재생할 수 없음"),
    "Video playback failed.": ("视频播放失败。", "動画の再生に失敗しました。", "동영상 재생에 실패했습니다."),
    "Pin to Top": ("置顶", "先頭に移動", "맨 위로"),
    "Pin %@ to Top": ("将 %@ 置顶", "%@ を先頭に移動", "%@ 맨 위로 이동"),
    "All Cameras": ("全部相机", "すべてのカメラ", "모든 카메라"),
    "Handheld": ("手持", "ハンドヘルド", "핸드헬드"),
    "Drones": ("航拍", "ドローン", "드론"),
    "Cinema": ("电影机", "シネマ", "시네마"),
    "Product images could not be loaded. Please rebuild the app.": ("产品图加载失败，请重新构建 App。", "製品画像を読み込めません。アプリを再ビルドしてください。", "제품 이미지를 불러올 수 없습니다. 앱을 다시 빌드하세요."),
    "Start with your camera.": ("从你的相机开始。", "まず、カメラを選ぼう。", "카메라부터 선택하세요."),
    "Choose a model. Its official LUT is already here.": ("选好机型，官方 LUT 已经就位。", "機種を選ぶだけ。公式 LUT は準備済みです。", "모델을 선택하세요. 공식 LUT가 준비되어 있습니다."),
    "Find your camera": ("查找相机", "カメラを検索", "카메라 찾기"),
    "Loading cameras…": ("正在加载相机…", "カメラを読み込み中…", "카메라 불러오는 중…"),
    "All processing stays on your Mac.": ("所有处理，都在你的 Mac。", "すべての処理を Mac の中で。", "모든 처리는 Mac 안에서 이루어집니다."),
    "Cameras": ("款相机", "機種", "개 카메라"),
    "Series image": ("系列示意图", "シリーズ画像", "시리즈 이미지"),
    "Reference LUTs": ("参考 LUT", "参照用 LUT", "참고용 LUT"),
    "Change Camera": ("更换相机", "カメラを変更", "카메라 변경"),
    "Back to Workspace": ("返回工作台", "ワークスペースに戻る", "작업 공간으로 돌아가기"),
    "A little less Log. A lot more life.": ("让色彩，回到画面里。", "Log に、色を取り戻す。", "Log 영상에 색을 되돌리세요."),
    "On your Mac": ("本机处理", "Mac 内で処理", "Mac에서 처리"),
    "Conversion LUT": ("转换 LUT", "変換 LUT", "변환 LUT"),
    "Compare original and converted": ("比较原片与转换效果", "元の映像と変換後を比較", "원본과 변환 결과 비교"),
    "Rotate preview 90° clockwise": ("顺时针旋转预览 90°", "プレビューを時計回りに90°回転", "미리보기를 시계 방향으로 90° 회전"),
    "Drop your footage here.": ("把素材拖进来。", "映像をここにドロップ。", "영상을 여기에 놓으세요."),
    "Or add videos to start with a before-and-after preview.": ("也可以添加视频，先看看还原前后。", "動画を追加すると、変換前後を比較できます。", "동영상을 추가하고 변환 전후를 비교하세요."),
    "Your clips": ("你的素材", "クリップ", "내 클립"),
    "Your clips will appear here.": ("添加的素材会出现在这里。", "追加したクリップがここに表示されます。", "추가한 클립이 여기에 표시됩니다."),
    "Export destination": ("导出到", "書き出し先", "내보낼 위치"),
    "Export": ("导出", "書き出し", "내보내기"),
    "Convert and Export": ("转换并导出", "変換して書き出す", "변환 및 내보내기"),
    "Check the recording mode": ("确认素材录制模式", "撮影モードを確認", "촬영 모드 확인"),
    "Don't ask again": ("不再提醒", "今後表示しない", "다시 표시하지 않기"),
    "Only convert original %@ clips. Normal, HLG, or previously converted videos can produce incorrect colors.": ("请确认这些视频是 %@ 模式录制、尚未转换的原片。普通模式、HLG 或已转换的视频再次还原，可能导致色彩异常。", "未変換の %@ 素材のみを変換してください。通常モード、HLG、または変換済みの動画では、色が正しく表示されないことがあります。", "변환하지 않은 %@ 원본 영상만 변환하세요. 일반 모드, HLG 또는 이미 변환된 동영상은 색상이 잘못 표시될 수 있습니다."),
    "1 video pending": ("1 个视频待导出", "1 本の動画が待機中", "동영상 1개 대기 중"),
    "%lld videos pending": ("%lld 个视频待导出", "%lld 本の動画が待機中", "동영상 %lld개 대기 중"),
    "All done": ("全部完成", "すべて完了", "모두 완료"),
    "Export complete": ("导出完成", "書き出し完了", "내보내기 완료"),
    "1 video was saved to %@.": ("1 个视频已保存到 %@。", "1 本の動画を %@ に保存しました。", "동영상 1개를 %@에 저장했습니다."),
    "%lld videos were saved to %@.": ("%lld 个视频已保存到 %@。", "%lld 本の動画を %@ に保存しました。", "동영상 %lld개를 %@에 저장했습니다."),
    "Ready": ("就绪", "準備完了", "준비됨"),
    "Converting": ("转换中", "変換中", "변환 중"),
    "Completed": ("已完成", "完了", "완료"),
    "Failed": ("失败", "失敗", "실패"),
    "Cancelled": ("已取消", "キャンセル済み", "취소됨"),
    "Choose videos or a folder of DJI footage.": ("选择视频或包含 DJI 素材的文件夹。", "動画または DJI 素材のフォルダを選択してください。", "동영상 또는 DJI 영상 폴더를 선택하세요."),
    "Add Videos": ("添加视频", "動画を追加", "동영상 추가"),
    "No supported videos were found. Choose MOV, MP4, or M4V files.": ("未找到支持的视频。请选择 MOV、MP4 或 M4V 文件。", "対応する動画がありません。MOV、MP4、M4V ファイルを選択してください。", "지원되는 동영상이 없습니다. MOV, MP4 또는 M4V 파일을 선택하세요."),
    "Choose a folder for converted videos. Original files stay unchanged.": ("选择转换后视频的保存文件夹。原始文件保持不变。", "変換した動画の保存先を選択してください。元のファイルは変更されません。", "변환된 동영상의 저장 폴더를 선택하세요. 원본 파일은 변경되지 않습니다."),
    "Choose Folder": ("选择文件夹", "フォルダを選択", "폴더 선택"),
    "DJI Cameras": ("DJI 相机", "DJI カメラ", "DJI 카메라"),
    "Bundled LUTs": ("内置 LUT", "内蔵 LUT", "내장 LUT"),
    "Dismiss": ("关闭", "閉じる", "닫기"),
    "Clear Queue": ("清空队列", "キューを消去", "대기열 지우기"),
    "Remove Clip": ("移除素材", "クリップを削除", "클립 제거"),
    "Recorded %@": ("拍摄于 %@", "撮影日時：%@", "촬영 일시: %@"),
    "Recording date unknown": ("拍摄日期未知", "撮影日時不明", "촬영 일시 알 수 없음"),
    "Clear all clips?": ("清空所有素材？", "すべてのクリップを消去しますか？", "모든 클립을 지우시겠습니까?"),
    "This removes all clips from the queue. Original and exported files stay unchanged.": ("这将从队列中移除所有素材，原片和已导出的文件不会被删除。", "キューからすべてのクリップを削除します。元のファイルと書き出したファイルは削除されません。", "대기열에서 모든 클립을 제거합니다. 원본과 내보낸 파일은 삭제되지 않습니다."),
    "Preparing preview…": ("正在生成预览…", "プレビューを準備中…", "미리보기 준비 중…"),
    "Original": ("原始画面", "元の映像", "원본"),
    "Rec.709 Preview": ("Rec.709 预览", "Rec.709 プレビュー", "Rec.709 미리보기"),
    "Original and converted video preview": ("原始视频与转换后的视频预览", "元の動画と変換後のプレビュー", "원본 및 변환된 동영상 미리보기"),
    "Preview Unavailable": ("无法预览", "プレビューできません", "미리보기를 사용할 수 없음"),
    "From Log to Color": ("让 Log 重现色彩", "Log 映像を鮮やかに", "Log 영상에 색을 더하세요"),
    "Choose your camera and conversion LUT, then add videos. Processing stays on your Mac.": ("选择相机和转换 LUT，然后添加视频。所有处理均在 Mac 本地完成。", "カメラと変換 LUT を選び、動画を追加してください。処理はすべて Mac 内で行われます。", "카메라와 변환 LUT를 선택한 후 동영상을 추가하세요. 모든 처리는 Mac에서 이루어집니다."),
    "Videos": ("视频", "動画", "동영상"),
    "HEVC · 10-bit · Rec.709": ("HEVC · 10 位 · Rec.709", "HEVC · 10 ビット · Rec.709", "HEVC · 10비트 · Rec.709"),
    "Show in Finder": ("在访达中显示", "Finder で表示", "Finder에서 보기"),
    "Drop videos or a folder here": ("将视频或文件夹拖到这里", "動画またはフォルダをここにドロップ", "동영상 또는 폴더를 여기에 놓으세요"),
    "Output Folder…": ("输出文件夹…", "出力フォルダ…", "출력 폴더…"),
    "Cancel": ("取消", "キャンセル", "취소"),
    "Convert All": ("全部转换", "すべて変換", "모두 변환"),
    "Color Conversion": ("色彩转换", "色変換", "색상 변환"),
    "Match the LUT to the recording mode used by your camera.": ("LUT 必须与相机录制时使用的色彩模式匹配。", "カメラの撮影モードに合った LUT を選択してください。", "카메라의 촬영 모드에 맞는 LUT를 선택하세요."),
    "Vivid": ("鲜艳", "鮮やか", "선명하게"),
    "Standard": ("标准", "標準", "표준"),
    "Archived · Conversion unavailable": ("已收录 · 暂不支持转换", "保管済み · 変換未対応", "보관됨 · 변환 미지원"),
    "These are original Log clips in the selected recording mode.": ("这些视频是使用所选模式录制、尚未转换的 Log 原片。", "これらは選択した撮影モードの未変換 Log 素材です。", "이 영상은 선택한 촬영 모드로 기록된 미변환 Log 원본입니다."),
    "Do not apply a conversion LUT to Normal, HLG, or previously converted videos.": ("请勿对普通模式、HLG 或已转换的视频再次应用还原 LUT。", "通常モード、HLG、変換済みの動画には変換 LUT を適用しないでください。", "일반 모드, HLG 또는 이미 변환된 동영상에는 변환 LUT를 적용하지 마세요."),
    "This LUT is included for reference. The first version exports 3D Log-to-Rec.709 conversions only.": ("此 LUT 已内置供参考。首版仅支持 3D Log 到 Rec.709 的转换导出。", "この LUT は参照用です。初版は 3D Log から Rec.709 への変換出力のみ対応しています。", "이 LUT는 참고용으로 포함되어 있습니다. 첫 버전은 3D Log에서 Rec.709로의 변환 내보내기만 지원합니다."),
    "DJI Official Source": ("DJI 官方来源", "DJI 公式配布元", "DJI 공식 출처"),
    "Original files stay unchanged. Exporting creates new encoded videos.": ("原始文件保持不变。导出会生成重新编码的视频。", "元のファイルは変更されません。書き出し時に新しい動画をエンコードします。", "원본 파일은 변경되지 않습니다. 내보내기는 새로 인코딩된 동영상을 만듭니다."),
    "Unspecified": ("未指定", "未指定", "지정되지 않음"),
    "LogLift for DJI": ("LogLift for DJI", "LogLift for DJI", "LogLift for DJI"),
}
CORE = {
    "Bundled LUT resources are missing or invalid.": ("内置 LUT 资源缺失或无效。", "内蔵 LUT リソースが見つからないか無効です。", "내장 LUT 리소스가 없거나 유효하지 않습니다."),
    "The LUT file failed its integrity check.": ("LUT 文件未通过完整性校验。", "LUT ファイルの整合性検証に失敗しました。", "LUT 파일 무결성 검사에 실패했습니다."),
    "The CUBE file is incomplete or invalid.": ("CUBE 文件不完整或无效。", "CUBE ファイルが不完全か無効です。", "CUBE 파일이 불완전하거나 유효하지 않습니다."),
    "This LUT format is not supported for conversion yet.": ("暂不支持使用此格式的 LUT 转换。", "この LUT 形式はまだ変換に対応していません。", "이 LUT 형식의 변환은 아직 지원되지 않습니다."),
    "This video format or track layout is not supported.": ("不支持此视频格式或轨道结构。", "この動画形式またはトラック構成には対応していません。", "이 동영상 형식 또는 트랙 구성은 지원되지 않습니다."),
    "Video processing failed.": ("视频处理失败。", "動画の処理に失敗しました。", "동영상 처리에 실패했습니다."),
    "An output file already exists. Choose another folder or rename the source.": ("输出文件已存在。请选择其他文件夹或重命名源文件。", "出力ファイルが存在します。別のフォルダを選ぶか、元のファイル名を変更してください。", "출력 파일이 이미 존재합니다. 다른 폴더를 선택하거나 원본 이름을 변경하세요."),
}


def write(path, table):
    strings = {}
    for source, translations in sorted(table.items()):
        strings[source] = {"extractionState": "manual", "localizations": {
            locale: {"stringUnit": {"state": "translated", "value": value}}
            for locale, value in zip(("en", "zh-Hans", "ja", "ko"), (source, *translations))
        }}
    path.write_text(json.dumps({"sourceLanguage": "en", "strings": strings, "version": "1.0"},
                               ensure_ascii=False, indent=2) + "\n")


if __name__ == "__main__":
    write(ROOT / "LogBatch/Resources/Localizable.xcstrings", APP)
    write(ROOT / "Core/Resources/Localizable.xcstrings", CORE)

