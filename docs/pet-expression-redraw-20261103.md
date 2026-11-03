# 桌宠身份统一与引导限定彩蛋

版本：1.4.1+66。

## 身份规范

- 以 `assets/images/pet_chibi.png` 为主参照，而非旧锁屏图。
- 统一粉色长发与刘海、紫色眼睛、右侧白色雏菊发夹、奶油色开衫、酒红领结、深蓝裙子、短身大头比例和深棕色圆润描线。
- 普通生气使用小幅皱眉、鼓脸与握拳；彩蛋使用同一人物更强烈的皱眉与叉腰姿态。
- 两张新图均使用内置 imagegen 编辑模式生成，保留 RGBA 透明背景，已替换项目内实际引用的 `pet_angry.png` 和 `pet_rage.png`。旧版可从 Git 历史取回。

## 彩蛋入口

- 仅进行中的新手引导可以触发：同一步累计 6 次耐心计数后结束引导并激活应用内锁屏。
- 两次误点后仍软化为可继续的步骤；提前跳过、推进步骤会结束或重置计数。自由参观步骤不计错。
- 普通点击、摸头、拖动、跳舞及投喂不会触发锁屏。
- 应用默认不自动开始引导，用户可在设置中选择重看。锁屏沿用原先无界面出口、重启应用退出的彩蛋形式。

## 最终生成提示词

### 普通生气

Reference/edit target: `pet_chibi.png`; `transparent_background=true`.

> EDIT TARGET: the attached existing Sakura Read chibi pet sprite. Produce ONE final game sprite on genuinely transparent background. Precisely preserve this girl's identity and the existing soft Japanese chibi cel illustration style: very large round head, tiny short body about two heads tall, long pastel pink hair with the same bangs, large PURPLE eyes, white five-petal daisy hair clip with yellow center on viewer-right, cream cardigan with burgundy neck accent, dark navy pleated skirt, same socks and burgundy shoes, dark brown hand-drawn rounded outline, warm flat pastel shading. Change ONLY expression and a small arm pose to a cute mildly angry/pouting expression: brows angled inward, purple eyes still the same size and design, lightly puffed cheeks and a tiny frown; hands clenched near chest, book tucked under an arm if needed. Keep the same round face, hair silhouette, outfit, body proportions, palette, and rendering detail as reference. Full body centered with all hair, hands and shoes visible, matching reference scale and pose footprint. No anger symbols, no text, no hearts, no floor shadow, no background. Avoid taller body, blue eyes, white shirt, new costume, sharp anime face, realistic rendering. This must look like another facial expression of the exact same pet, not a redesigned character.

### 彩蛋生气

References: canonical `pet_chibi.png` and the new ordinary angry sprite; `transparent_background=true`.

> Create ONE stronger-angry expression sprite of the EXACT SAME Sakura Read chibi girl as both reference images. Image 1 is the canonical identity, costume and body proportions. Image 2 is the freshly approved ordinary angry expression; match its rendering and design so these sprites form one coherent set. Keep pastel pink long hair, same bangs and silhouette, white five-petal daisy hair clip with yellow center on viewer-right, big PURPLE eyes and same rounded face, very large head and short two-head-high body, cream cardigan and burgundy ribbon, dark navy pleated skirt, matching socks and burgundy shoes, thick rounded dark-brown outline. Mood: very annoyed, stubborn chibi pout, furrowed brows and slightly narrowed purple eyes, puffed cheeks and a small downturned mouth. Hands on hips, feet together, full body facing front. This is for a playful dark-screen easter egg, not horror: no red eyes, no blue eyes, no blood, no weapons, no new clothing, no white shirt, no realistic face, no taller body. Preserve exact character consistency and soft pastel flat cel shading. Full body centered all hair and shoes visible. Genuine transparent background, no floor shadow, no text, no anger icons, no scene. Only expression and arm pose differ from the existing girl.

## 验证

- 两张新资产均为 RGBA PNG，具有真实透明区域；已目视核对身份特征与全身构图。
- 22 个针对性测试通过：引导流程、只触发一次、手动重看入口、锁屏层表现、版本一致性。
- Flutter 静态检查无问题。

- Android arm64 release 构建成功（1.4.1+66，约 51.4 MB）。
