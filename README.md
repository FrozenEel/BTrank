# BTrank

[中文](#中文) · [English](#english)

---

## 中文

### 项目简介

BTrank 是一个用 SwiftUI 写的 iOS 小应用（iOS 18.4+）：输入一个人的五项评分，再选择一些「补正」，App 按一套固定公式算出 0–10 的综合分，并把结果放进排行榜。

主要功能：

- 五项评分（颜值、身材、穿搭、气质、性格，各 0–10）+ 补正选项，计算最终得分
- 同一个人可以多次评分，排行榜按**平均分**排名
- 雷达图展示各项得分（单次结果、个人平均）
- 排行榜可导出为图片并分享
- 数据保存在本机（`UserDefaults`），支持左滑删除

> 所有数值与公式都是娱乐性质的设定，下文逐项列出。

### 计算流程总览

```
五项评分 ──► 归一化 ──► 综合基础分
                         │
                         ▼
        ① 财富补正（保底 8 分）
        ② 舍得补正（共同承担 / 舍得 / 不舍得）
        ③ 加分补正：学历 / 事业 / 上镜度（加法或乘法，按 6 分分界）
        ④ 扣分补正：化妆 / 滤镜（按百分比相乘）
                         │
                         ▼
                 限制在 0 ~ 10 → 最终得分
```

补正的顺序固定为：**综合基础分 → 财富 → 舍得 → 学历/事业/上镜度 → 化妆/滤镜 → 封顶 0~10**。

### 1. 输入参数

| 参数 | 含义 | 范围 |
|---|---|---|
| 颜值 | 基础颜值评分 | 0–10 |
| 身材 | 身材评分 | 0–10 |
| 穿搭 | 穿搭评分 | 0–10 |
| 气质 | 气质评分 | 0–10 |
| 性格 | 性格评分 | 0–10 |

输入为空按 0 处理，超出范围会被限制到 0–10。

### 2. 归一化

```
f(x) = x / 10          (x 限制在 0 ~ 10，结果在 0 ~ 1)
```

记颜值、身材、穿搭、气质、性格归一化后分别为 `r, b, c, l, p`。线性归一化意味着：每一项 5 分 = 0.5，全 5 分且无补正时综合基础分恰好是 5.0。

### 3. 综合基础分

```
基础分 = 10 × ( wR·r + wB·b + 0.15·c + 0.10·l + 0.15·p )
```

| 维度 | 权重 | 颜值偏低时（r < 0.3，即颜值 < 3 分） |
|---|---|---|
| 颜值 `wR` | 0.30 | 0.27 |
| 身材 `wB` | 0.30 | 0.33 |
| 穿搭 | 0.15 | 0.15 |
| 气质 | 0.10 | 0.10 |
| 性格 | 0.15 | 0.15 |

- 颜值与身材的权重之和固定为 0.6（`wB = 0.6 − wR`），总权重为 1。
- 设计意图：颜值越低，身材占比越高，让颜值一般的人也可以通过身材加分。

### 4. 补正

#### 4.1 财富补正（开 / 关）

```
基础分 = max(基础分, 8)
```

开启后，综合基础分低于 8 的按 8 算；不低于 8 的不受影响。参数：`wealthBase = 8.0`。

#### 4.2 舍得补正（三选一）

对伴侣在情感上的消费态度，排在财富补正之后计算。

| 选项 | 含义 | 效果 |
|---|---|---|
| 共同承担 | 默认 | 不加不扣 |
| 舍得 | 愿意为伴侣花钱 | 指数曲线加分 |
| 不舍得 | 不愿在情感中花钱 | 非线性扣分 |

**舍得（加分）**——分越高加得越多（指数曲线），4 分及以下没有补正，5 分 +0.5，7 分 +2.1（即 7 → 9.1），之后固定在 +2.1：

```
x = min(基础分, 7) − 4
加分 = a · (q^x − 1)        （基础分 ≤ 4 时为 0）
q = (−1 + √(1 + 4·(2.1/0.5 − 1))) / 2 ≈ 1.3574
a = 0.5 / (q − 1)          ≈ 1.3989
基础分 = 基础分 + 加分
```

| 基础分 | 4 | 4.5 | 5 | 5.5 | 6 | 6.5 | 7 | ≥7 |
|---|---|---|---|---|---|---|---|---|
| 舍得后 | 4.00 | 4.73 | 5.50 | 6.31 | 7.18 | 8.10 | 9.10 | 基础分 + 2.1 |

参数：`generosityStart = 4`、`generosityPeak = 7`、`generosityAt5 = 0.5`、`generosityAtPeak = 2.1`。

**不舍得（扣分）**——分越高扣得越少：

```
基础分 ≥ 7:   扣 0
5 < 基础分 < 7: 扣 0.7 + (2 − 0.7) · ((7 − 基础分) / 2)^2
基础分 ≤ 5:   扣 2
基础分 = max(0, 基础分 − 扣分)
```

| 基础分 | ≤1 | 3 | 5 | 5.5 | 6 | 6.5 | 6.99 | ≥7 |
|---|---|---|---|---|---|---|---|---|
| 扣分 | 2（扣到 0 封底） | 2 | 2 | 1.43 | 1.03 | 0.78 | 0.70 | 0 |
| 扣后 | 0 | 1.00 | 3.00 | 4.07 | 4.98 | 5.72 | 6.29 | 不变 |

参数：`stingyFullAt = 5`、`stingyNoneAt = 7`、`stingyMax = 2`、`stingyStart = 0.7`（刚低于 7 分时的起扣值）、`stingyExponent = 2`。

> 注意：财富补正先于舍得计算，所以同时开启财富时，基础分被抬到 ≥ 8，「不舍得」不会再扣分；「舍得」则会在 8 分上固定 +2.1，两者同开必然满分。

#### 4.3 加分补正：学历 / 事业 / 上镜度

每项折算成「点数」：

| 补正 | 取值 | 点数 |
|---|---|---|
| 学历 | 有 | 1 |
| 事业 | 有 | 1 |
| 上镜度 | 上镜 / 一般 / 不上镜 | 0 / 0.5 / 1（越不上镜，补得越多） |

```
满额点数  fullPoints = 1 + 1 + 1 = 3          （学历 + 事业 + 不上镜）
补正强度  s = 总点数 / 3                       （0 ~ 1，即 0% ~ 100%）
```

补正强度按综合基础分的高低走两套算法（分界线 `threshold = 6`）：

```
基础分 < 6:   分数 = 基础分 + 0.5 × s              （加法：满额 +0.5，所有人加得一样多）
基础分 ≥ 6:   分数 = 基础分 × (1 + 0.125 × s)      （乘法：满额 ×1.125，分越高加得越多）
```

参数：`fullBonus = 0.5`、`fullMultiplier = 1.125`。设计目标：全 5 分的普通人满额补正后是 5.5；基础分 8 分的人满额补正后是 9.0。

| 单项 | 占满额 | 5 分的人 | 8 分的人 |
|---|---|---|---|
| 学历 | 33% | 5.17 | 8.33 |
| 事业 | 33% | 5.17 | 8.33 |
| 不上镜 | 33% | 5.17 | 8.33 |
| 一般 | 17% | 5.08 | 8.17 |
| 全部拉满 | 100% | 5.50 | 9.00 |

#### 4.4 扣分补正：化妆 / 滤镜

两项各自独立，默认关闭，开启后选「低 / 中 / 高」。不管分数高低，一律按百分比相乘（另一套规则，不走补正强度）：

```
单项扣分比例 = 6.25% × (档位 / 3)       档位：低=1，中=2，高=3
扣分乘数     = (1 − 化妆扣分) × (1 − 滤镜扣分)
分数         = 分数 × 扣分乘数
```

| 档位 | 低 | 中 | 高 |
|---|---|---|---|
| 化妆 | −2.083% | −4.167% | −6.25% |
| 滤镜 | −2.083% | −4.167% | −6.25% |

参数：`maxDeduction = 0.0625`。两项都选「高」时叠加 −12.1%（×0.8789）。

#### 4.5 最终得分

```
最终得分 = clamp( 加分补正后的分数 × 扣分乘数, 0, 10 )
```

### 5. 计算示例

| 情况 | 结果 |
|---|---|
| 五项全 5 分，无补正 | 5.00 |
| 五项全 5 分，学历 + 事业 + 不上镜 | 5.50 |
| 五项全 8 分，学历 + 事业 + 不上镜 | 9.00 |
| 五项全 5 分，仅财富 | 8.00 |
| 五项全 7 分，仅舍得 | 9.10 |
| 五项全 5 分，仅不舍得 | 3.00 |
| 五项全 5 分，仅化妆「高」 | 4.69 |
| 五项全 5 分，化妆「高」+ 滤镜「高」 | 4.39 |

### 6. 排行榜与平均

- 同一个名字（忽略大小写和首尾空格）可以多次评分，每次保存一条记录（得分、各项分、当时启用的补正）。
- 排行榜按所有记录得分的**平均值**排名；个人详情页显示平均雷达图（各项评分的平均）和历史记录，可单条删除。
- 旧版本的数据会自动迁移；旧版本没有各项评分的记录不参与雷达图，但总分仍计入平均。

### 7. 参数速查（`BTrank/Models.swift`）

| 常量 | 值 | 含义 |
|---|---|---|
| 权重 | 0.30 / 0.30 / 0.15 / 0.10 / 0.15 | 颜值 / 身材 / 穿搭 / 气质 / 性格 |
| 颜值偏低阈值 | r < 0.3 | 触发 0.27 / 0.33 权重 |
| `wealthBase` | 8.0 | 财富补正保底分 |
| `generosityStart` / `Peak` | 4 / 7 | 舍得曲线起点 / 峰值 |
| `generosityAt5` / `AtPeak` | 0.5 / 2.1 | 舍得在 5 分、7 分处的加分 |
| `stingyFullAt` / `NoneAt` | 5 / 7 | 不舍得扣满 / 不扣的分界 |
| `stingyMax` / `Start` / `Exponent` | 2 / 0.7 / 2 | 最大扣分 / 起扣值 / 衰减指数 |
| `threshold` | 6.0 | 加分补正加法 / 乘法分界线 |
| `fullBonus` | 0.5 | 低于分界线时满额补正加多少分 |
| `fullMultiplier` | 1.125 | 不低于分界线时满额补正乘数 |
| `fullPoints` | 3 | 满额点数（学历 + 事业 + 不上镜） |
| `maxDeduction` | 0.0625 | 化妆 / 滤镜「高」档最大扣分 |

### 8. 项目结构与运行

```
BTrank/
├── BTrankApp.swift         应用入口
├── ContentView.swift       界面：输入页、补正、排行榜、个人详情、导出图片
├── Models.swift            数据模型 + 评分引擎（全部公式在这里）
├── ScoreViewModel.swift    状态、计算、排行榜、持久化
└── RadarChartView.swift    雷达图
```

用 Xcode 打开 `BTrank.xcodeproj`，选择 iOS 18.4 及以上的模拟器或真机运行即可，无第三方依赖。

### 免责声明与致谢

本 App 仅供娱乐，所有数值和公式均为娱乐性质的设定，不构成对任何人的客观评价。

本 App 的灵感来源于「上善若水」和「蛇鼠一窝」的群友，感谢他们的帮助，没有他们的帮助便没有这款产品。

---

## English

### About

BTrank is a small SwiftUI iOS app (iOS 18.4+). You enter five ratings for a person, pick some optional "adjustments", and the app computes a 0–10 score with a fixed set of formulas and puts it on a leaderboard.

Features:

- Five ratings (Looks, Body, Style, Aura, Personality — each 0–10) plus adjustment options produce a final score
- The same person can be rated multiple times; the leaderboard ranks by the **average**
- Radar charts show the individual ratings (per result, and per-person average)
- The leaderboard can be exported as an image and shared
- Data is stored locally (`UserDefaults`); swipe to delete

> All numbers and formulas are entertainment settings, listed in full below.

### Pipeline overview

```
5 ratings ──► normalize ──► composite base score
                              │
                              ▼
          1. Wealth adjustment (floor of 8)
          2. Generosity adjustment (shared / generous / stingy)
          3. Bonus adjustments: education / career / photogenic (additive or multiplicative, split at 6)
          4. Deductions: makeup / filter (percentage multipliers)
                              │
                              ▼
                      clamp to 0 – 10 → final score
```

Order of operations is fixed: **composite base → wealth → generosity → education/career/photogenic → makeup/filter → clamp 0–10**.

### 1. Inputs

| Parameter | Meaning | Range |
|---|---|---|
| Looks (颜值) | Base looks rating | 0–10 |
| Body (身材) | Body rating | 0–10 |
| Style (穿搭) | Outfit / styling rating | 0–10 |
| Aura (气质) | Temperament / presence rating | 0–10 |
| Personality (性格) | Personality rating | 0–10 |

Empty input counts as 0; values outside the range are clamped to 0–10.

### 2. Normalization

```
f(x) = x / 10          (x clamped to 0..10, result in 0..1)
```

Call the normalized values `r, b, c, l, p` (looks, body, style, aura, personality). Because it is linear, 5 maps to 0.5, so five 5s with no adjustments give a composite base of exactly 5.0.

### 3. Composite base score

```
base = 10 × ( wR·r + wB·b + 0.15·c + 0.10·l + 0.15·p )
```

| Dimension | Weight | When looks are low (r < 0.3, i.e. looks < 3) |
|---|---|---|
| Looks `wR` | 0.30 | 0.27 |
| Body `wB` | 0.30 | 0.33 |
| Style | 0.15 | 0.15 |
| Aura | 0.10 | 0.10 |
| Personality | 0.15 | 0.15 |

- The looks and body weights always add up to 0.6 (`wB = 0.6 − wR`); the total weight is 1.
- Intent: the lower the looks rating, the more weight goes to body, so a good body can still make up for lower looks.

### 4. Adjustments

#### 4.1 Wealth (on / off)

```
base = max(base, 8)
```

When on, a composite base below 8 is treated as 8; scores of 8 or more are unaffected. Parameter: `wealthBase = 8.0`.

#### 4.2 Generosity (one of three)

Attitude toward spending on a partner emotionally. Applied after the wealth adjustment.

| Option | Meaning | Effect |
|---|---|---|
| Shared (共同承担) | Default | No change |
| Generous (舍得) | Willing to spend on a partner | Exponential bonus |
| Stingy (不舍得) | Unwilling to spend in the relationship | Non-linear penalty |

**Generous (bonus)** — the higher the score, the bigger the bonus (exponential). Nothing at 4 or below, +0.5 at 5, +2.1 at 7 (7 → 9.1), then a flat +2.1:

```
x = min(base, 7) − 4
bonus = a · (q^x − 1)       (0 when base ≤ 4)
q = (−1 + √(1 + 4·(2.1/0.5 − 1))) / 2 ≈ 1.3574
a = 0.5 / (q − 1)           ≈ 1.3989
base = base + bonus
```

| Base | 4 | 4.5 | 5 | 5.5 | 6 | 6.5 | 7 | ≥7 |
|---|---|---|---|---|---|---|---|---|
| After | 4.00 | 4.73 | 5.50 | 6.31 | 7.18 | 8.10 | 9.10 | base + 2.1 |

Parameters: `generosityStart = 4`, `generosityPeak = 7`, `generosityAt5 = 0.5`, `generosityAtPeak = 2.1`.

**Stingy (penalty)** — the higher the score, the smaller the penalty:

```
base ≥ 7:          penalty 0
5 < base < 7:      penalty 0.7 + (2 − 0.7) · ((7 − base) / 2)^2
base ≤ 5:          penalty 2
base = max(0, base − penalty)
```

| Base | ≤1 | 3 | 5 | 5.5 | 6 | 6.5 | 6.99 | ≥7 |
|---|---|---|---|---|---|---|---|---|
| Penalty | 2 (floored at 0) | 2 | 2 | 1.43 | 1.03 | 0.78 | 0.70 | 0 |
| After | 0 | 1.00 | 3.00 | 4.07 | 4.98 | 5.72 | 6.29 | unchanged |

Parameters: `stingyFullAt = 5`, `stingyNoneAt = 7`, `stingyMax = 2`, `stingyStart = 0.7` (the penalty just below 7), `stingyExponent = 2`.

> Note: wealth is applied before generosity. With wealth on, the base is lifted to ≥ 8, so "Stingy" no longer deducts anything, while "Generous" adds a flat +2.1 at 8 — both together always reach the maximum score.

#### 4.3 Bonus adjustments: education / career / photogenic

Each is converted into "points":

| Adjustment | Value | Points |
|---|---|---|
| Education | yes | 1 |
| Career | yes | 1 |
| Photogenic level | photogenic / average / unphotogenic | 0 / 0.5 / 1 (the less photogenic, the larger the compensation) |

```
full points  fullPoints = 1 + 1 + 1 = 3        (education + career + unphotogenic)
strength     s = total points / 3              (0..1, i.e. 0%..100%)
```

Strength is applied with one of two rules depending on the composite base (split at `threshold = 6`):

```
base < 6:   score = base + 0.5 × s              (additive: full strength = +0.5, same for everyone)
base ≥ 6:   score = base × (1 + 0.125 × s)      (multiplicative: full strength = ×1.125, higher scores gain more)
```

Parameters: `fullBonus = 0.5`, `fullMultiplier = 1.125`. Design goals: an average person (all 5s) with full bonuses reaches 5.5; someone at base 8 with full bonuses reaches 9.0.

| Item | Share of full | At base 5 | At base 8 |
|---|---|---|---|
| Education | 33% | 5.17 | 8.33 |
| Career | 33% | 5.17 | 8.33 |
| Unphotogenic | 33% | 5.17 | 8.33 |
| Average | 17% | 5.08 | 8.17 |
| All maxed | 100% | 5.50 | 9.00 |

#### 4.4 Deductions: makeup / filter

Independent, off by default; when on, choose Low / Medium / High. These always apply as percentage multipliers regardless of score (a separate rule that does not use bonus strength):

```
deduction per item = 6.25% × (level / 3)       level: Low=1, Medium=2, High=3
multiplier         = (1 − makeup) × (1 − filter)
score              = score × multiplier
```

| Level | Low | Medium | High |
|---|---|---|---|
| Makeup | −2.083% | −4.167% | −6.25% |
| Filter | −2.083% | −4.167% | −6.25% |

Parameter: `maxDeduction = 0.0625`. Both set to High stack to −12.1% (×0.8789).

#### 4.5 Final score

```
final = clamp( bonus-adjusted score × deduction multiplier, 0, 10 )
```

### 5. Worked examples

| Case | Result |
|---|---|
| All five ratings 5, no adjustments | 5.00 |
| All 5, education + career + unphotogenic | 5.50 |
| All 8, education + career + unphotogenic | 9.00 |
| All 5, wealth only | 8.00 |
| All 7, generous only | 9.10 |
| All 5, stingy only | 3.00 |
| All 5, makeup High only | 4.69 |
| All 5, makeup High + filter High | 4.39 |

### 6. Leaderboard and averaging

- The same name (case-insensitive, trimmed) can be rated many times; each rating stores a record (score, per-dimension ratings, adjustments used).
- The leaderboard ranks by the **average** of all scores; the person detail page shows an average radar chart (average of each dimension) and the history, with per-record deletion.
- Data from older versions is migrated automatically; records from older versions that lack per-dimension ratings are excluded from the radar chart but still count toward the average score.

### 7. Parameter reference (`BTrank/Models.swift`)

| Constant | Value | Meaning |
|---|---|---|
| Weights | 0.30 / 0.30 / 0.15 / 0.10 / 0.15 | Looks / Body / Style / Aura / Personality |
| Low-looks threshold | r < 0.3 | Switches to 0.27 / 0.33 weights |
| `wealthBase` | 8.0 | Floor score for the wealth adjustment |
| `generosityStart` / `Peak` | 4 / 7 | Start / peak of the generous curve |
| `generosityAt5` / `AtPeak` | 0.5 / 2.1 | Bonus at base 5 / at the peak |
| `stingyFullAt` / `NoneAt` | 5 / 7 | Full-penalty / no-penalty bounds for stingy |
| `stingyMax` / `Start` / `Exponent` | 2 / 0.7 / 2 | Max penalty / start value / decay exponent |
| `threshold` | 6.0 | Additive / multiplicative split for bonuses |
| `fullBonus` | 0.5 | Max additive bonus below the threshold |
| `fullMultiplier` | 1.125 | Max multiplier at or above the threshold |
| `fullPoints` | 3 | Points for full strength (education + career + unphotogenic) |
| `maxDeduction` | 0.0625 | Max deduction for makeup / filter at High |

### 8. Project layout and running

```
BTrank/
├── BTrankApp.swift         App entry point
├── ContentView.swift       UI: input, adjustments, leaderboard, person detail, image export
├── Models.swift            Data models + scoring engine (all formulas live here)
├── ScoreViewModel.swift    State, calculation, leaderboard, persistence
└── RadarChartView.swift    Radar chart
```

Open `BTrank.xcodeproj` in Xcode and run on an iOS 18.4+ simulator or device. No third-party dependencies.

### Disclaimer and Thanks

This app is for entertainment only. All numbers and formulas are entertainment settings and do not constitute an objective evaluation of anyone.

The inspiration for this app comes from the members of the "上善若水" and "蛇鼠一窝" group chats. Thank you for your help — without it this app would not exist.
