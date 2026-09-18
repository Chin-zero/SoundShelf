import json,pathlib
rules=[]
def add(kind,dim,label,keys): rules.append(dict(kind=kind,dimension=dim,label=label,keywords=keys.split('|')))
def group(kind,dim,entries):
 for label,keys in entries: add(kind,dim,label,keys)
group('音效','类别',[
('转场','whoosh|transition|transitions|sweeper|wipe|flyby|转场|飞过|飞跃|扫场|掠过'),('强调与冲击','hit|hits|impact|impacts|boom|boomer|boomers|clash|重击|冲击|撞击|冲突|低音'),('人物与动作','humans|human|footstep|footsteps|combat|gore|人声|脚步|搏击|拳|呼吸'),('物件与生活','household|camera|typewriter|clock|cloth|衣服|布料|生活|家庭|快门|时钟|打字'),('自然与动物','weather|jungle|rain|wind|water|bird|birds|animal|animals|天气|雨|风声|水声|动物|鸟|森林'),('环境与空间','ambience|ambient|surroundings|surround|crowd|人群|环境|环绕'),('交通与机械','vehicles|vehicle|machines|machine|engine|car|train|飞机|飞船|车辆|交通|机器|齿轮|引擎'),('电子与界面','technology|future|sci fi|科技|电子|未来|故障|提示'),('影视与悬疑','cinematic|trailer|scary|suspense|horror|jumpscare|jumpscares|drones|atmospheres|space|电影|悬疑|恐怖|氛围|太空|深空'),('节奏与乐器','rhythm|cymbals|horn|drum|节奏|鼓点|铜管'),('趣味与卡通','cartoon|funny|comedy|boing|卡通|搞笑|弹跳')])
group('音效','声音',[
('掠过／呼啸','whoosh|whooshes|flyby|swoosh|whip|呼啸|划过|掠过|飞过'),('上升／吸入','riser|risers|rise|absorb|上升|吸收|吸入'),('下降','fall|down|下降|下落'),('重击','hit|hits|impact|impacts|重击|冲击'),('低频轰鸣','boom|boomer|boomers|braaaam|rumble|轰鸣|低频'),('脚步','footstep|footsteps|walking|脚步|走路'),('搏击','combat|punch|kick|fight|搏击|拳|脚踢'),('呼吸','breath|breathing|呼吸|喘气'),('拍手','clap|clapping|拍手|鼓掌'),('布料摩擦','cloth|fabric|clothing|布料|衣服|衣物'),('拉链','zipper|zip|拉链'),('开关门','door|门'),('快门','camera|shutter|快门|相机'),('打字／键盘','typewriter|keyboard|typing|打字|键盘'),('时钟／倒计时','clock|tick|ticking|时钟|倒计时'),('玻璃破碎','glass|shatter|玻璃|碎裂'),('人群','crowd|人群'),('风声','wind|windy|风声'),('雨声','rain|rainfall|雨'),('雷声','thunder|雷'),('流水／海浪','water|stream|ocean|wave|waves|水流|海浪|流水'),('鸟鸣','bird|birds|鸟'),('火焰','fire|flame|火焰|燃烧'),('汽车','car|cars|汽车'),('火车','train|火车'),('飞机','airplane|aircraft|jet|飞机'),('引擎','engine|motor|引擎|发动机'),('机械运转','machine|machines|gear|gears|机器|齿轮'),('点击／通知','click|notification|beep|点击|提示|通知'),('故障／电流','glitch|electric|static|故障|电流'),('心跳','heartbeat|心跳'),('持续低鸣','drone|drones|hum|低鸣'),('鼓点','drum|drums|rhythm|鼓点|节奏'),('铜管／号角','horn|brass|号角|铜管'),('镲片','cymbal|cymbals|镲')])
group('音效','材质',[('布料','cloth|fabric|布料'),('皮革','leather|皮革'),('纸张','paper|纸'),('塑料','plastic|塑料'),('木头','wood|wooden|木'),('金属','metal|metallic|金属'),('玻璃','glass|玻璃'),('水／液体','water|liquid|水|液体')])
group('音效','空间',[('室内','indoor|interior|room|室内'),('室外','outdoor|exterior|室外'),('近距离','close|near|近距离'),('远距离','distant|far|远处'),('混响','reverb|echo|混响|回声'),('干声','dry|干声')])
group('音效','时间形态',[('循环','loop|looping|循环'),('短促','short|短促'),('长尾','tail|long|长尾'),('渐强','build|riser|risers|渐强'),('反向','reverse|reversed|反向')])
group('音乐','场景',[('穿搭／美妆','穿搭|美妆|fashion'),('旅行／旅拍','旅行|旅拍|travel'),('航拍','航拍|aerial'),('延时摄影','延时|timelapse'),('婚礼','婚礼|wedding'),('日常 Vlog','vlog'),('采访／口播','采访|口播|interview'),('宣传／颁奖','宣传|年会|颁奖'),('学习／思考','学习|思考|刷题'),('影视剪辑','电影|影视|cinematic')])
group('音乐','用途',[('卡点','卡点|踩点|节奏类'),('铺底','背景音乐|伴奏|ambient'),('开场','intro|opener|开场'),('收尾','outro|ending|收尾'),('高潮','epic|史诗|燃点|震撼'),('快剪','快剪')])
group('音乐','风格',[('爵士','jazz|jazzy|爵士'),('放克','funk|funky|放克'),('嘻哈','hip hop|hiphop|嘻哈'),('电子','electronic|edm|电子'),('民谣','folk|民谣'),('古典','classical|古典'),('摇滚','rock|摇滚'),('氛围','ambient|氛围'),('史诗／影视','epic|cinematic|史诗'),('Lo-fi','lo fi|lofi'),('流行','pop|流行')])
group('音乐','乐器',[('钢琴','piano|钢琴'),('木吉他','acoustic guitar|木吉他'),('电吉他','electric guitar|电吉他'),('弦乐','strings|violin|弦乐|小提琴'),('铜管','brass|trumpet|铜管|小号'),('合成器','synth|synthesizer|合成器'),('打击乐','percussion|drums|打击乐')])
group('音乐','人声',[('纯音乐','instrumental|纯音乐|无人声'),('哼唱','humming|哼唱')])
group('','情绪',[('松弛','chill|relax|relaxing|松弛|放松'),('温柔','gentle|温柔'),('清新','fresh|清新'),('俏皮／欢快','happy|playful|欢快|俏皮'),('甜蜜','sweet|romantic|甜蜜|浪漫'),('热血／振奋','epic|inspiring|燃点|热血|励志'),('忧伤','sad|melancholy|忧伤|悲伤'),('紧张／悬疑','suspense|tense|tension|悬疑|紧张'),('恐怖','horror|scary|jumpscares|恐怖|惊吓')])
group('','听感',[('柔和','soft|柔和'),('厚重','heavy|厚重'),('轻盈','light|轻盈'),('尖锐','sharp|尖锐'),('低沉','low|deep|低沉'),('清脆','crisp|清脆'),('失真','distorted|distortion|失真')])
group('音乐','用途',[('节奏／卡点','节奏|踩点|卡点')])
group('音乐','场景',[('企业宣传','企业宣传'),('游记','游记'),('升格／慢动作','升格|慢动作'),('星空延时','星空|timelapser')])
group('音乐','风格',[('高级感','高级感|高逼格'),('文艺','文艺')])
group('音乐','听感',[('震撼／大气','震撼|大气|磅礴')])
group('音乐','能量',[('轻快律动','轻high')])
group('音乐','节奏',[('无节奏','无节奏')])
p=pathlib.Path(__file__).parent/'taxonomy.json'; p.write_text(json.dumps(rules,ensure_ascii=False,indent=2))
print(len(rules),'classification rules')
