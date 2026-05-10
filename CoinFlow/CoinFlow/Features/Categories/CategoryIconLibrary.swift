//  CategoryIconLibrary.swift
//  CoinFlow · 分类图标精选库
//
//  设计原则：
//   - SF Symbols 系统符号（单色，自动响应 selectedColor，跨主题一致）
//   - 20 个分组覆盖记账高频场景；每组 8-12 个图标
//   - 中文别名：用户搜"咖啡"能命中 cup.and.saucer.fill
//   - 全部静态数据，App 体积无感知
//
//  数据契约：
//   - 所有 systemName 必须在 iOS 17 已 GA（部署目标 16.0；少数 17+ 限定的避开）
//   - 所有图标用 .fill 或 default 单一变体，避免风格混乱
//   - 不引入 emoji / 多色变体（multicolor / hierarchical 由 UI 层决定渲染）
//
//  搜索语义：
//   - 优先匹配 systemName 子串
//   - 再匹配 aliases 任一中文/英文词
//   - 不区分大小写

import Foundation

/// 单个图标条目：系统符号名 + 中文别名集合
struct CategoryIcon: Identifiable, Hashable {
    let systemName: String
    let aliases: [String]
    var id: String { systemName }
}

/// 一个分组：标题（chip 显示）+ 图标列表
struct CategoryIconGroup: Identifiable, Hashable {
    let title: String
    let icons: [CategoryIcon]
    var id: String { title }
}

enum CategoryIconLibrary {

    // MARK: - 全部分组（20 类）

    static let groups: [CategoryIconGroup] = [
        // 1. 餐饮
        .init(title: "餐饮", icons: [
            .init(systemName: "fork.knife", aliases: ["餐饮", "吃饭", "用餐", "正餐", "饭"]),
            .init(systemName: "fork.knife.circle.fill", aliases: ["餐厅", "聚餐", "饭店"]),
            .init(systemName: "cup.and.saucer.fill", aliases: ["咖啡", "下午茶", "茶", "饮品"]),
            .init(systemName: "mug.fill", aliases: ["奶茶", "杯子", "饮料"]),
            .init(systemName: "wineglass.fill", aliases: ["酒", "红酒", "聚会", "宴请"]),
            .init(systemName: "birthday.cake.fill", aliases: ["蛋糕", "甜品", "生日", "烘焙"]),
            .init(systemName: "popcorn.fill", aliases: ["零食", "爆米花", "小吃"]),
            .init(systemName: "carrot.fill", aliases: ["蔬菜", "买菜", "生鲜"]),
            .init(systemName: "fish.fill", aliases: ["海鲜", "鱼", "肉类"]),
            .init(systemName: "takeoutbag.and.cup.and.straw.fill", aliases: ["外卖", "快餐", "美团", "饿了么"]),
            .init(systemName: "frying.pan.fill", aliases: ["做饭", "厨房", "下厨"]),
            .init(systemName: "leaf.fill", aliases: ["素食", "健康餐", "沙拉"])
        ]),

        // 2. 交通
        .init(title: "交通", icons: [
            .init(systemName: "car.fill", aliases: ["打车", "汽车", "滴滴", "出租"]),
            .init(systemName: "car.2.fill", aliases: ["拼车", "顺风车"]),
            .init(systemName: "bus.fill", aliases: ["公交", "巴士"]),
            .init(systemName: "tram.fill", aliases: ["地铁", "轻轨", "电车"]),
            .init(systemName: "bicycle", aliases: ["自行车", "单车", "骑行"]),
            .init(systemName: "scooter", aliases: ["电瓶车", "电动车"]),
            .init(systemName: "fuelpump.fill", aliases: ["加油", "汽油", "油费"]),
            .init(systemName: "parkingsign.circle.fill", aliases: ["停车", "停车费", "车位"]),
            .init(systemName: "airplane", aliases: ["飞机", "机票", "航班"]),
            .init(systemName: "ferry.fill", aliases: ["轮船", "渡轮"]),
            .init(systemName: "tram.circle.fill", aliases: ["高铁", "火车", "动车", "12306"]),
            .init(systemName: "road.lanes", aliases: ["高速", "过路费", "ETC"])
        ]),

        // 3. 购物
        .init(title: "购物", icons: [
            .init(systemName: "bag.fill", aliases: ["购物", "买东西", "购物袋"]),
            .init(systemName: "cart.fill", aliases: ["购物车", "超市", "京东", "淘宝"]),
            .init(systemName: "creditcard.fill", aliases: ["信用卡", "刷卡", "支付"]),
            .init(systemName: "gift.fill", aliases: ["礼物", "礼品", "送礼"]),
            .init(systemName: "tag.fill", aliases: ["折扣", "优惠", "打折"]),
            .init(systemName: "shippingbox.fill", aliases: ["快递", "包裹", "物流"]),
            .init(systemName: "basket.fill", aliases: ["菜篮", "购物篮"]),
            .init(systemName: "tshirt.fill", aliases: ["衣服", "服装", "T恤"]),
            .init(systemName: "shoe.fill", aliases: ["鞋", "鞋子", "球鞋"]),
            .init(systemName: "handbag.fill", aliases: ["包", "手袋", "背包"])
        ]),

        // 4. 日用
        .init(title: "日用", icons: [
            .init(systemName: "bubbles.and.sparkles.fill", aliases: ["清洁", "洗护", "日化"]),
            .init(systemName: "drop.fill", aliases: ["洗漱", "沐浴", "牙膏"]),
            .init(systemName: "archivebox.fill", aliases: ["纸巾", "抽纸", "卫生纸", "杂物"]),
            .init(systemName: "trash.fill", aliases: ["垃圾袋", "废弃物"]),
            .init(systemName: "lightbulb.fill", aliases: ["灯泡", "电器小件"]),
            .init(systemName: "bolt.fill", aliases: ["电池", "充电"]),
            .init(systemName: "key.fill", aliases: ["钥匙", "锁具"]),
            .init(systemName: "hammer.fill", aliases: ["五金", "工具", "维修小件"]),
            .init(systemName: "scissors", aliases: ["剪刀", "理发", "美发"]),
            .init(systemName: "paintbrush.fill", aliases: ["装饰", "油漆", "DIY"])
        ]),

        // 5. 居家
        .init(title: "居家", icons: [
            .init(systemName: "house.fill", aliases: ["居家", "家", "房子"]),
            .init(systemName: "house.lodge.fill", aliases: ["民宿", "短租"]),
            .init(systemName: "bed.double.fill", aliases: ["床", "卧室", "家具"]),
            .init(systemName: "sofa.fill", aliases: ["沙发", "客厅"]),
            .init(systemName: "lamp.table.fill", aliases: ["灯具", "家装"]),
            .init(systemName: "washer.fill", aliases: ["洗衣机", "家电"]),
            .init(systemName: "refrigerator.fill", aliases: ["冰箱", "厨电"]),
            .init(systemName: "stove.fill", aliases: ["燃气", "煤气", "燃气费"]),
            .init(systemName: "drop.degreesign.fill", aliases: ["水费", "自来水"]),
            .init(systemName: "bolt.house.fill", aliases: ["电费", "用电"]),
            .init(systemName: "wrench.adjustable.fill", aliases: ["维修", "保修", "家修"]),
            .init(systemName: "key.horizontal.fill", aliases: ["房租", "物业", "租房"])
        ]),

        // 6. 医疗
        .init(title: "医疗", icons: [
            .init(systemName: "cross.case.fill", aliases: ["医疗", "医院", "看病"]),
            .init(systemName: "stethoscope", aliases: ["挂号", "门诊", "医生"]),
            .init(systemName: "pills.fill", aliases: ["药", "药品", "买药", "药店"]),
            .init(systemName: "cross.vial.fill", aliases: ["化验", "体检", "抽血"]),
            .init(systemName: "syringe.fill", aliases: ["注射", "疫苗", "打针"]),
            .init(systemName: "bandage.fill", aliases: ["包扎", "绷带"]),
            .init(systemName: "heart.text.square.fill", aliases: ["心电", "体检报告"]),
            .init(systemName: "lungs.fill", aliases: ["呼吸", "肺", "感冒"]),
            .init(systemName: "cross.case.circle.fill", aliases: ["牙科", "牙医", "洗牙", "口腔"]),
            .init(systemName: "eye.fill", aliases: ["眼科", "配镜", "视力"])
        ]),

        // 7. 通讯
        .init(title: "通讯", icons: [
            .init(systemName: "phone.fill", aliases: ["电话", "话费", "通话"]),
            .init(systemName: "iphone.gen3", aliases: ["手机", "话费充值"]),
            .init(systemName: "antenna.radiowaves.left.and.right", aliases: ["流量", "信号", "基站"]),
            .init(systemName: "wifi", aliases: ["WiFi", "宽带", "网络"]),
            .init(systemName: "envelope.fill", aliases: ["邮件", "邮箱"]),
            .init(systemName: "message.fill", aliases: ["短信", "消息"]),
            .init(systemName: "video.fill", aliases: ["视频通话", "会议"]),
            .init(systemName: "headphones", aliases: ["耳机", "通话设备"]),
            .init(systemName: "simcard.fill", aliases: ["SIM 卡", "电话卡"])
        ]),

        // 8. 教育
        .init(title: "教育", icons: [
            .init(systemName: "book.fill", aliases: ["书", "图书", "买书", "看书"]),
            .init(systemName: "books.vertical.fill", aliases: ["藏书", "书库", "学习资料"]),
            .init(systemName: "graduationcap.fill", aliases: ["学费", "毕业", "教育"]),
            .init(systemName: "pencil.tip.crop.circle.fill", aliases: ["文具", "学习用品"]),
            .init(systemName: "studentdesk", aliases: ["上课", "教室"]),
            .init(systemName: "newspaper.fill", aliases: ["报纸", "订阅", "杂志"]),
            .init(systemName: "doc.text.fill", aliases: ["论文", "资料", "文档"]),
            .init(systemName: "play.rectangle.fill", aliases: ["网课", "课程", "知识付费"]),
            .init(systemName: "globe.asia.australia.fill", aliases: ["外语", "翻译", "出国"]),
            .init(systemName: "checkmark.seal.fill", aliases: ["证书", "考证", "认证"])
        ]),

        // 9. 娱乐
        .init(title: "娱乐", icons: [
            .init(systemName: "gamecontroller.fill", aliases: ["游戏", "玩"]),
            .init(systemName: "tv.fill", aliases: ["电视", "节目"]),
            .init(systemName: "play.tv.fill", aliases: ["视频会员", "腾讯视频", "爱奇艺", "优酷", "B站"]),
            .init(systemName: "music.note", aliases: ["音乐", "歌曲", "网易云", "QQ音乐"]),
            .init(systemName: "headphones.circle.fill", aliases: ["音乐会员", "Apple Music"]),
            .init(systemName: "ticket.fill", aliases: ["票", "演出票", "电影票"]),
            .init(systemName: "film.fill", aliases: ["电影", "影院", "看电影"]),
            .init(systemName: "popcorn.circle.fill", aliases: ["影院零食", "电影零食"]),
            .init(systemName: "guitars.fill", aliases: ["乐器", "现场", "乐队"]),
            .init(systemName: "party.popper.fill", aliases: ["派对", "聚会", "庆祝"]),
            .init(systemName: "die.face.5.fill", aliases: ["桌游", "游戏厅", "棋牌"])
        ]),

        // 10. 运动
        .init(title: "运动", icons: [
            .init(systemName: "figure.run", aliases: ["跑步", "运动", "锻炼"]),
            .init(systemName: "figure.walk", aliases: ["步行", "散步"]),
            .init(systemName: "figure.strengthtraining.traditional", aliases: ["健身", "撸铁", "举重"]),
            .init(systemName: "dumbbell.fill", aliases: ["哑铃", "健身房", "私教"]),
            .init(systemName: "figure.yoga", aliases: ["瑜伽", "拉伸", "塑形"]),
            .init(systemName: "figure.pool.swim", aliases: ["游泳", "泳池"]),
            .init(systemName: "figure.basketball", aliases: ["篮球", "球类"]),
            .init(systemName: "soccerball", aliases: ["足球", "球赛"]),
            .init(systemName: "figure.skiing.downhill", aliases: ["滑雪", "雪场"]),
            .init(systemName: "tennis.racket", aliases: ["网球", "羽毛球", "球拍"]),
            .init(systemName: "figure.hiking", aliases: ["徒步", "登山", "户外"]),
            .init(systemName: "stopwatch.fill", aliases: ["计时", "训练"])
        ]),

        // 11. 旅行
        .init(title: "旅行", icons: [
            .init(systemName: "airplane.departure", aliases: ["旅行", "出差", "出发"]),
            .init(systemName: "suitcase.fill", aliases: ["行李", "箱子", "出行"]),
            .init(systemName: "beach.umbrella.fill", aliases: ["度假", "海边"]),
            .init(systemName: "tent.fill", aliases: ["露营", "野营"]),
            .init(systemName: "map.fill", aliases: ["地图", "导航", "线路"]),
            .init(systemName: "mappin.and.ellipse", aliases: ["景点", "打卡地"]),
            .init(systemName: "binoculars.fill", aliases: ["观光", "游览"]),
            .init(systemName: "camera.fill", aliases: ["拍照", "相机", "摄影"]),
            .init(systemName: "wallet.pass.fill", aliases: ["护照", "出境", "通行证"]),
            .init(systemName: "fork.knife.circle", aliases: ["特色餐厅", "异地用餐"])
        ]),

        // 12. 宠物
        .init(title: "宠物", icons: [
            .init(systemName: "pawprint.fill", aliases: ["宠物", "猫狗", "爪印"]),
            .init(systemName: "dog.fill", aliases: ["狗", "犬", "汪"]),
            .init(systemName: "cat.fill", aliases: ["猫", "喵", "猫咪"]),
            .init(systemName: "fish", aliases: ["鱼", "观赏鱼", "鱼缸"]),
            .init(systemName: "bird.fill", aliases: ["鸟", "鹦鹉"]),
            .init(systemName: "tortoise.fill", aliases: ["乌龟", "爬宠"]),
            .init(systemName: "ant.fill", aliases: ["昆虫", "异宠"]),
            .init(systemName: "leaf", aliases: ["绿植", "宠物草"]),
            .init(systemName: "cross.case", aliases: ["宠物医疗", "宠物医院"]),
            .init(systemName: "bag", aliases: ["宠物粮", "猫粮", "狗粮"])
        ]),

        // 13. 育儿
        .init(title: "育儿", icons: [
            .init(systemName: "figure.and.child.holdinghands", aliases: ["育儿", "亲子", "带娃"]),
            .init(systemName: "stroller.fill", aliases: ["婴儿车", "推车"]),
            .init(systemName: "teddybear.fill", aliases: ["玩具", "毛绒"]),
            .init(systemName: "figure.2.and.child.holdinghands", aliases: ["婴儿用品", "母婴", "亲子"]),
            .init(systemName: "figure.child", aliases: ["儿童", "小孩"]),
            .init(systemName: "balloon.2.fill", aliases: ["生日", "派对", "庆生"]),
            .init(systemName: "book.closed.fill", aliases: ["绘本", "童书"]),
            .init(systemName: "puzzlepiece.extension.fill", aliases: ["拼图", "益智玩具"]),
            .init(systemName: "drop.halffull", aliases: ["奶粉", "辅食"]),
            .init(systemName: "graduationcap", aliases: ["兴趣班", "早教"])
        ]),

        // 14. 数码
        .init(title: "数码", icons: [
            .init(systemName: "laptopcomputer", aliases: ["笔记本", "电脑", "Mac"]),
            .init(systemName: "desktopcomputer", aliases: ["台式机", "主机", "PC"]),
            .init(systemName: "ipad", aliases: ["平板", "iPad"]),
            .init(systemName: "iphone", aliases: ["手机", "iPhone"]),
            .init(systemName: "applewatch", aliases: ["手表", "智能手表"]),
            .init(systemName: "headphones.circle", aliases: ["耳机", "蓝牙耳机"]),
            .init(systemName: "speaker.wave.3.fill", aliases: ["音箱", "音响"]),
            .init(systemName: "keyboard.fill", aliases: ["键盘", "外设"]),
            .init(systemName: "computermouse.fill", aliases: ["鼠标", "外设"]),
            .init(systemName: "camera.aperture", aliases: ["相机", "摄影器材"]),
            .init(systemName: "memorychip.fill", aliases: ["内存", "存储", "硬盘"]),
            .init(systemName: "cable.connector", aliases: ["数据线", "配件"])
        ]),

        // 15. 美妆
        .init(title: "美妆", icons: [
            .init(systemName: "sparkles", aliases: ["美容", "护肤"]),
            .init(systemName: "drop.circle.fill", aliases: ["精华", "面霜", "护肤品"]),
            .init(systemName: "eyebrow", aliases: ["眉妆", "化妆品"]),
            .init(systemName: "mouth.fill", aliases: ["口红", "唇彩"]),
            .init(systemName: "comb.fill", aliases: ["美发", "造型", "梳子"]),
            .init(systemName: "scissors.circle.fill", aliases: ["剪发", "理发店"]),
            .init(systemName: "face.smiling.inverse", aliases: ["美颜", "面膜"]),
            .init(systemName: "hands.sparkles.fill", aliases: ["美甲", "美容仪"]),
            .init(systemName: "sun.max.fill", aliases: ["防晒", "紫外线"])
        ]),

        // 16. 工作
        .init(title: "工作", icons: [
            .init(systemName: "briefcase.fill", aliases: ["工作", "公文包", "职场"]),
            .init(systemName: "building.2.fill", aliases: ["公司", "办公楼"]),
            .init(systemName: "person.crop.rectangle.fill", aliases: ["名片", "联系人"]),
            .init(systemName: "doc.fill", aliases: ["文件", "文档", "工作资料"]),
            .init(systemName: "folder.fill", aliases: ["文件夹", "归档"]),
            .init(systemName: "printer.fill", aliases: ["打印", "复印"]),
            .init(systemName: "paperplane.fill", aliases: ["发送", "邮件办公"]),
            .init(systemName: "calendar", aliases: ["日历", "日程"]),
            .init(systemName: "clock.fill", aliases: ["加班", "时间"]),
            .init(systemName: "tray.full.fill", aliases: ["收件箱", "任务"])
        ]),

        // 17. 工资
        .init(title: "工资", icons: [
            .init(systemName: "dollarsign.circle.fill", aliases: ["工资", "薪水", "薪资", "收入"]),
            .init(systemName: "yensign.circle.fill", aliases: ["人民币", "RMB", "元"]),
            .init(systemName: "banknote.fill", aliases: ["钞票", "现金"]),
            .init(systemName: "creditcard.and.123", aliases: ["代发", "工资卡"]),
            .init(systemName: "chart.bar.fill", aliases: ["奖金", "绩效", "提成"]),
            .init(systemName: "gift.circle.fill", aliases: ["年终奖", "福利"]),
            .init(systemName: "medal.fill", aliases: ["奖励", "勋章"]),
            .init(systemName: "rosette", aliases: ["补贴", "津贴"]),
            .init(systemName: "doc.text.below.ecg.fill", aliases: ["报销", "发票"])
        ]),

        // 18. 转账
        .init(title: "转账", icons: [
            .init(systemName: "arrow.left.arrow.right", aliases: ["转账", "互转"]),
            .init(systemName: "arrow.up.right.circle.fill", aliases: ["转出", "支付"]),
            .init(systemName: "arrow.down.right.circle.fill", aliases: ["转入", "到账"]),
            .init(systemName: "arrow.uturn.backward", aliases: ["退款", "退回"]),
            .init(systemName: "arrow.triangle.2.circlepath", aliases: ["互转", "调拨"]),
            .init(systemName: "person.2.fill", aliases: ["AA", "拆账"]),
            .init(systemName: "qrcode", aliases: ["扫码", "收款码"]),
            .init(systemName: "wallet.pass.fill", aliases: ["钱包", "电子钱包"]),
            .init(systemName: "indianrupeesign.circle.fill", aliases: ["外币", "汇款"]),
            .init(systemName: "scanner.fill", aliases: ["扫一扫", "二维码"])
        ]),

        // 19. 投资
        .init(title: "投资", icons: [
            .init(systemName: "chart.line.uptrend.xyaxis", aliases: ["理财", "投资", "基金"]),
            .init(systemName: "chart.bar.xaxis", aliases: ["股票", "证券"]),
            .init(systemName: "bitcoinsign.circle.fill", aliases: ["数字货币", "加密货币"]),
            .init(systemName: "building.columns.fill", aliases: ["银行", "存款"]),
            .init(systemName: "lock.shield.fill", aliases: ["保险", "保障"]),
            .init(systemName: "house.and.flag.fill", aliases: ["房产", "不动产"]),
            .init(systemName: "scalemass.fill", aliases: ["黄金", "贵金属"]),
            .init(systemName: "percent", aliases: ["利息", "收益率"]),
            .init(systemName: "doc.plaintext.fill", aliases: ["合同", "保单"])
        ]),

        // 20. 其他
        .init(title: "其他", icons: [
            .init(systemName: "ellipsis.circle", aliases: ["其他", "杂项"]),
            .init(systemName: "questionmark.circle.fill", aliases: ["未知", "待分类"]),
            .init(systemName: "star.fill", aliases: ["收藏", "标记"]),
            .init(systemName: "flag.fill", aliases: ["标记", "重点"]),
            .init(systemName: "bookmark.fill", aliases: ["书签", "记号"]),
            .init(systemName: "pin.fill", aliases: ["置顶", "图钉"]),
            .init(systemName: "heart.fill", aliases: ["收藏", "喜爱"]),
            .init(systemName: "lightbulb.max.fill", aliases: ["灵感", "想法"]),
            .init(systemName: "trash.circle.fill", aliases: ["删除", "废弃"])
        ])
    ]

    // MARK: - 默认值

    /// 新建分类时的默认 icon（出现在 Add Sheet 初始预览）
    static let defaultIconName: String = "tag.fill"

    /// 所有图标扁平列表（搜索"全部"时用）
    static var allIcons: [CategoryIcon] {
        groups.flatMap { $0.icons }
    }

    // MARK: - 搜索

    /// 按 query 过滤；空 query → 返回 nil（让 UI 显示分组结构）
    /// 命中规则：
    ///   1. systemName 子串（不区分大小写）
    ///   2. aliases 任一子串（不区分大小写）
    static func search(_ query: String) -> [CategoryIcon]? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return nil }
        // 去重：同一图标可能既在 systemName 命中又在 aliases 命中
        var seen = Set<String>()
        var result: [CategoryIcon] = []
        for icon in allIcons {
            let nameHit = icon.systemName.lowercased().contains(q)
            let aliasHit = icon.aliases.contains { $0.lowercased().contains(q) }
            if (nameHit || aliasHit) && !seen.contains(icon.systemName) {
                seen.insert(icon.systemName)
                result.append(icon)
            }
        }
        return result
    }

    // MARK: - 预设分类升级映射

    /// DefaultSeeder 预设分类的「升级图标表」：
    ///   key = preset 分类 id，value = 新精选库里更贴切的 SF Symbol
    /// 仅用于 seeder 首次种子；已存在的分类不会被覆盖（保护用户已修改的图标）。
    static let presetIconUpgrades: [String: String] = [
        "preset-expense-food":     "fork.knife",
        "preset-expense-transit":  "car.fill",
        "preset-expense-shopping": "bag.fill",
        "preset-expense-housing":  "house.fill",
        "preset-expense-fun":      "gamecontroller.fill",
        "preset-expense-medical":  "cross.case.fill",
        "preset-expense-edu":      "graduationcap.fill",      // 比 book.fill 更贴"教育"
        "preset-expense-other":    "ellipsis.circle",
        "preset-income-salary":    "dollarsign.circle.fill",
        "preset-income-bonus":     "gift.fill",
        "preset-income-transfer":  "arrow.left.arrow.right",
        "preset-income-refund":    "arrow.uturn.backward",
        "preset-income-invest":    "chart.line.uptrend.xyaxis",
        "preset-income-other":     "ellipsis.circle"
    ]
}
