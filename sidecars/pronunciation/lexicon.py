#!/usr/bin/env python3
"""Words the voice says wrongly, respelled into words it says correctly.

The agent's voice mispronounces a specific set of words badly enough that a
listener notices and a recogniser cannot recover them: 企業 comes out as
奇幼, 規劃 as 窺 what, 訓練 as 碎裂. Measured, not guessed -- `corpus.py`
holds what it was measured on, `sidecars/tone_probe` holds the older
instrument, and `docs/decisions/taiwan-mandarin-voice-candidates.md` holds
the run.

The obvious fixes were tried and are gone. The model does not accept pinyin
annotation: `qi1業` renders as 七一一, it reads the digits. Its unquantised
build mispronounces the same words. A different model is better on isolated
words and no better on real sentences while taking twice as long to speak.

What works is spelling the word as a different word that sounds the same.
Writing 氣業 makes the voice say qì yè, which is what 企業 is, and the
recogniser then writes 企業 back -- the sound is right and the characters
it was reached through are nobody's business. Every entry below was
verified that way: rendered, transcribed, and accepted only when the
original word came back.

One entry is not a homophone but a script: 開發 renders as 缺乏, and writing
it Simplified, 开发, fixes it. That is the same trick -- another spelling of
the same word -- and it is worth knowing the model has a second door.

Two rules this must never break.

**Render only.** These respellings exist between the text and the
synthesiser. They must never reach the conversation, storage, or the
screen, or the user will read 氣業 in their own transcript and rightly
conclude the agent cannot spell.

**Same sound, always.** An entry that changes the sound is not a
pronunciation fix, it is the voice saying a different word. That is worse
than the defect it replaces, because it is invisible in text. It is also
what makes the table safe without a segmenter: 記錄 -> 記路 fires inside
登記錄音 too, and 登記路音 is read aloud identically. A polyphone at that
boundary is the one case where it would not be, which is why an entry whose
characters change reading with the word after them does not belong here.
"""

from __future__ import annotations

# word -> (respelling, what it said before, what it says now)
#
# The third field is what makes an entry auditable. Without it a future
# reader has a table of substitutions and no way to tell which are still
# needed, and a model upgrade would leave every one of them in place
# forever.
RESPELLINGS: dict[str, tuple[str, str, str]] = {
    "企業": ("氣業", "奇幼", "企業"),
    "危險": ("維險", "吸混", "危險"),
    "攜帶": ("西帶", "頭戴", "攜帶"),
    "品質": ("品直", "品機", "品質"),
    "蝸牛": ("刮牛", "犀牛", "蝸牛"),
    "音樂": ("音月", "音臥", "音樂"),
    "成長": ("成掌", "成整", "成長"),
    "編譯": ("邊譯", "偏西", "編譯"),
    "結構": ("潔構", "極口", "結構"),
    "檸檬": ("寧蒙", "雞蒙", "檸檬"),
    "確認": ("卻認", "誇引", "確認"),
    "壓力": ("押力", "姚莉", "壓力"),
    "學習": ("學席", "學修", "學習"),
    "計畫": ("記話", "記載", "計畫"),
    "邏輯": ("羅集", "no 集", "邏輯"),
    "佇列": ("住列", "數列", "佇列"),
    "合併": ("何病", "何翠", "合併"),
    "執行緒": ("執行序", "執行史", "執行緒"),
    "授權": ("受權", "少前", "授權"),
    "日誌": ("日治", "日式", "日誌"),
    "會議": ("會義", "會語", "會議"),
    "機器學習": ("機器學席", "機器學者", "機器學習"),
    "瀏覽器": ("流覽器", "雷亮記", "瀏覽器"),
    "物件": ("誤件", "誤解", "物件"),
    "規劃": ("規話", "窺 what", "規劃"),
    "訓練": ("迅練", "碎裂", "訓練"),
    "資料": ("姿料", "失料", "資料"),
    "資料庫": ("姿料庫", "失料苦", "資料庫"),
    "除錯": ("廚錯", "出錯", "除錯"),
    "電子郵件": ("電子游件", "雁字亮點", "電子郵件"),
    "鑰匙": ("要匙", "基石", "鑰匙"),
    "雨傘": ("雨散", "雨順", "雨傘"),
    "電視": ("店視", "驗數", "電視"),
    "客戶": ("刻戶", "撤戶", "客戶"),
    "感謝": ("感卸", "感結", "感謝"),
    "老闆": ("老板", "老計", "老闆"),
    "討厭": ("討燕", "投硬", "討厭"),
    "曾經": ("層經", "成經", "曾經"),
    "血液": ("血業", "雪葉", "血液"),
    "認識": ("認是", "認喜", "認識"),
    "下載": ("夏載", "差窄", "下載"),
    "刪除": ("山除", "參許", "刪除"),
    "查詢": ("茶詢", "插身", "查詢"),
    "檢查": ("減查", "見察", "檢查"),
    "溝通": ("勾通", "gay 通", "溝通"),
    "繼續": ("記序", "記住", "繼續"),
    "記錄": ("記路", "紀樂", "記錄"),
    "開發": ("开发", "切發", "開發"),
    "身高": ("深高", "升高", "身高"),
    "血壓": ("寫壓", "雪鴨", "血壓"),
    "韌帶": ("認帶", "輪待", "韌帶"),
    "纖維": ("先維", "七維", "纖維"),
    "駝背": ("陀背", "揪背", "駝背"),
    "視力": ("是力", "事理", "視力"),
    "餃子": ("腳子", "柚子", "餃子"),
    "豆漿": ("豆江", "鬥誦", "豆漿"),
    "水餃": ("水腳", "水右", "水餃"),
    "滷味": ("魯味", "除了", "滷味"),
    "鹹酥雞": ("閒酥雞", "鮮酥雞", "鹹酥雞"),
    "太鹹": ("太閒", "太先", "太鹹"),
    "飯店": ("犯店", "防彈", "飯店"),
    "距離": ("巨離", "T 裡", "距離"),
    "收費站": ("收廢站", "周慧戰", "收費站"),
    "社區": ("設區", "市區", "社區"),
    "快遞": ("快弟", "快帶", "快遞"),
    "獎金": ("獎斤", "講經", "獎金"),
    "稅金": ("睡金", "睡經", "稅金"),
    "帳單": ("丈單", "長丹", "帳單"),
    "匯款": ("惠款", "回款", "匯款"),
    "貸款": ("代款", "退糞", "貸款"),
    "憂鬱": ("優鬱", "you will", "憂鬱"),
    "尷尬": ("甘尬", "挫尬", "尷尬"),
    "羨慕": ("現慕", "尋木", "羨慕"),
    "崩潰": ("崩愧", "崩退", "崩潰"),
    "療癒": ("聊癒", "了意", "療癒"),
    "滿足": ("滿族", "敏竹", "滿足"),
    "其實": ("奇實", "啟示", "其實"),
    "畢竟": ("必竟", "b 減", "畢竟"),
    "快捷鍵": ("快捷件", "快捷卷", "快捷鍵"),
    "帳號": ("丈號", "強欺跳", "帳號"),
    "備份": ("貝份", "b 分", "備份"),
    "隱私": ("引私", "銀息", "隱私"),
    "蔥薑蒜": ("葱姜蒜", "界限算", "蔥薑蒜"),
    "檔案": ("档案", "產案", "檔案"),
    "網頁": ("网页", "盲友", "網頁"),
    "頁": ("页", "128 屆", "頁"),
    "領導": ("領岛", "引導", "領導"),
    "學院": ("學愿", "學驗", "學院"),
    "組織": ("組之", "組吃", "組織"),
    "工業": ("公業", "公爺", "工業"),
    "政治": ("政制", "正直", "政治"),
    "記者": ("計者", "自著", "記者"),
    "國際": ("國計", "國字", "國際"),
    "各種": ("个種", "個子", "各種"),
    "編輯": ("边輯", "偏激", "編輯"),
    "職業": ("直業", "直也", "職業"),
    "大學": ("大穴", "大所", "大學"),
    "人員": ("人原", "人云", "人員"),
    "機構": ("基構", "金勾", "機構"),
    "基礎": ("基楚", "基詞", "基礎"),
    "過程": ("過成", "過情", "過程"),
    "單位": ("單为", "單背", "單位"),
    "報告": ("抱告", "爆鍋", "報告"),
    "分別": ("紛別", "分彼", "分別"),
    "專業": ("專夜", "建議", "專業"),
    "旅遊": ("旅由", "雨油", "旅遊"),
    "實現": ("时現", "斜線", "實現"),
    "先進": ("先缙", "仙境", "先進"),
    "保護": ("宝護", "寶物", "保護"),
    "那裡": ("那理", "內裡", "那裡"),
    "新聞": ("心聞", "新門", "新聞"),
    "不僅": ("部僅", "不及", "不僅"),
    "豐富": ("風富", "封戶", "豐富"),
    "瞭解": ("了解", "留解", "瞭解"),
    "傳統": ("船統", "全統", "傳統"),
    "規模": ("規麽", "居我", "規模"),
    "實施": ("時施", "事實", "實施"),
    "心裡": ("心理", "森理", "心裡"),
    "下去": ("夏去", "下取", "下去"),
    "聲音": ("生音", "新聞", "聲音"),
    "汽車": ("气車", "氣叉", "汽車"),
    "事業": ("市業", "事有", "事業"),
    "報道": ("報盗", "報導", "報道"),
    "父親": ("复親", "世新", "父親"),
    "領域": ("領育", "領具", "領域"),
    "憲法": ("现法", "寫法", "憲法"),
    "鬥爭": ("鬥征", "鬥針", "鬥爭"),
    "兒子": ("而子", "日字", "兒子"),
    "現代": ("現带", "厭帶", "現代"),
    "直轄市": ("直辖市", "指幾世", "直轄市"),
    "積極": ("机極", "極其", "積極"),
    "擴大": ("括大", "曠大", "擴大"),
    "官員": ("关員", "關雲", "官員"),
    "考慮": ("考律", "逃慮", "考慮"),
    "擁有": ("擁友", "有有", "擁有"),
    "結合": ("節合", "結銷", "結合"),
    "開放": ("揩放", "拆放", "開放"),
    "別人": ("別仁", "鼻忍", "別人"),
    "綜合": ("綜和", "搓滑", "綜合"),
    "動物": ("動务", "動讀", "動物"),
    "導彈": ("導蛋", "倒彈", "導彈"),
    "發表": ("發婊", "小小的", "發表"),
    "質量": ("制量", "尺量", "質量"),
    "考試": ("考是", "討世", "考試"),
    "卻是": ("卻似", "這個詞式確實", "卻是"),
    "業務": ("業物", "厭惡", "業務"),
    "同樣": ("童樣", "東樣", "同樣"),
    "哪裡": ("哪理", "車禮", "哪裡"),
    "裝備": ("裝被", "裝 b", "裝備"),
    "經營": ("京營", "驚醒", "經營"),
    "經常": ("京常", "輕強", "經常"),
    "開展": ("開斩", "壞產", "開展"),
    "文學": ("聞學", "文火", "文學"),
    "還要": ("還藥", "海耀", "還要"),
    "女兒": ("女而", "五言", "女兒"),
    "圖片": ("途片", "土匹", "圖片"),
    "創造": ("創燥", "創咒", "創造"),
    "相當": ("乡當", "仙臟", "相當"),
    "資金": ("資今", "自引", "資金"),
    "變成": ("變城", "半程", "變成"),
    "區域": ("區育", "區議", "區域"),
    "創作": ("創做", "沖座", "創作"),
    "連續": ("連序", "簡訊", "連續"),
    "運輸": ("運书", "運虛", "運輸"),
    "貿易": ("貿亿", "木椅", "貿易"),
    "成績": ("成机", "誠之", "成績"),
    "正確": ("政確", "正錯", "正確"),
    "大臣": ("大陈", "大乘", "大臣"),
    "畢業": ("必業", "貶羽", "畢業"),
    "政權": ("政全", "正確的", "政權"),
    "發揮": ("發灰", "方曲", "發揮"),
    "遺址": ("遺紙", "移植", "遺址"),
    "身邊": ("深邊", "生變", "身邊"),
    "只有": ("指有", "隻有", "只有"),
    "適當": ("是當", "私藏", "適當"),
    "實踐": ("實建", "實性", "實踐"),
    "高興": ("高性", "高新", "高興"),
    "再次": ("在次", "在此", "再次"),
    "委員長": ("委原長", "委營長", "委員長"),
    "協議": ("協义", "學義", "協議"),
    "闖王": ("闯王", "魏王", "闖王"),
    "閱讀": ("月讀", "怨敵", "閱讀"),
    "進去": ("近去", "進取", "進去"),
    "紡織": ("纺织", "組組", "紡織"),
    "意識": ("意识", "意喜", "意識"),
    "兩側": ("兩策", "兩色", "兩側"),
    "網站": ("網战", "掌戰", "網站"),
    "製作": ("治作", "指做", "製作"),
    "檢察長": ("檢察掌", "檢查常", "檢察長"),
    "領導人": ("領岛人", "引導人", "領導人"),
    "事實": ("是實", "試試", "事實"),
    "永遠": ("勇遠", "用語", "永遠"),
    "變得": ("便得", "變的", "變得"),
    "劃分": ("化分", "waffen", "劃分"),
    "同學": ("童學", "童俗", "同學"),
    "礦產": ("况產", "臥蠶", "礦產"),
    "具備": ("具被", "句弊", "具備"),
    "性命": ("姓命", "姓名", "性命"),
    "隨即": ("隨級", "隨機", "隨即"),
    "現場": ("县場", "怨葬", "現場"),
    "論壇": ("論談", "輪的", "論壇"),
    "大規模": ("大規麽", "大居博", "大規模"),
    "威脅": ("威协", "微譽", "威脅"),
    "情緒": ("情续", "情趣", "情緒"),
    "民間": ("民监", "名詞", "民間"),
    "依據": ("一據", "遺跡", "依據"),
    "費用": ("废用", "say 用", "費用"),
    "這兒": ("這而", "這", "這兒"),
    "員工": ("員公", "雲中", "員工"),
    "藥物": ("要物", "要 5", "藥物"),
    "公斤": ("工斤", "公經", "公斤"),
    "標誌": ("標制", "標示", "標誌"),
    "螢幕": ("營幕", "實木", "螢幕"),
    "瓶頸": ("瓶景", "平起", "瓶頸"),
}


# Entries whose respelling reads differently *in the dictionary*, each with
# the reason it is right anyway. Everything else must read identically, and
# the tests hold it to that -- this is what keeps "same sound, always" from
# being a slogan.
#
# Seven of these force the Taiwan reading, which is the whole point of the
# oldest entries here and is exactly what a dictionary of mainland readings
# calls an error. One is the dictionary being wrong. One is a polyphone the
# dictionary resolves the other way and the voice does not.
READS_DIFFERENTLY: dict[str, str] = {
    "企業": "Taiwan reads qì yè; the dictionary says qǐ",
    "危險": "Taiwan reads wéi xiǎn; the dictionary says wēi",
    "攜帶": "Taiwan reads xī dài; the dictionary says xié",
    "品質": "Taiwan reads pǐn zhí; the dictionary says zhì",
    "蝸牛": "Taiwan reads guā niú; the dictionary says wō",
    "認識": "Taiwan reads rèn shì; the dictionary says shí",
    "血壓": "Taiwan reads xiě yā; the dictionary says xuè",
    "音樂": "樂 is yuè here and pypinyin reads it lè, so 月 is the right "
            "sound and the dictionary is the thing that is wrong",
    "雨傘": "散 is sǎn and sàn and the dictionary picks sàn; the carrier and "
            "the sentence both came back 雨傘, so the voice picks sǎn",
}


def respell(text: str, table: dict[str, tuple[str, str, str]] | None = None) -> str:
    """[text] with every known-mispronounced word swapped for its respelling.

    One left-to-right pass taking the longest entry that starts at each
    position, so nothing an entry writes is read by another one. Round after
    round of `str.replace` gave the same answer while the table held eleven
    words that shared no characters; at forty-eight, 檢查 and 查詢 overlap
    and the result depended on which came out of the dictionary first. This
    is also what `applyMisheardWords` does on the Dart side, and the two
    being the same is worth more than either being clever.

    Everything else is left exactly as written: this is a lookup, not a
    rewriter, and text the table has never been measured against must reach
    the synthesiser untouched.
    """
    entries = table if table is not None else RESPELLINGS
    words = sorted(entries, key=len, reverse=True)
    out: list[str] = []
    index = 0
    while index < len(text):
        for word in words:
            if text.startswith(word, index):
                out.append(entries[word][0])
                index += len(word)
                break
        else:
            out.append(text[index])
            index += 1
    return "".join(out)


def applied(text: str, table: dict[str, tuple[str, str, str]] | None = None) -> list[str]:
    """Which entries [text] would trigger, for logging what was changed.

    In the order they are reached, which is the order [respell] applies
    them, so a log line reads the way the sentence does.
    """
    entries = table if table is not None else RESPELLINGS
    words = sorted(entries, key=len, reverse=True)
    found: list[str] = []
    index = 0
    while index < len(text):
        for word in words:
            if text.startswith(word, index):
                if word not in found:
                    found.append(word)
                index += len(word)
                break
        else:
            index += 1
    return found
