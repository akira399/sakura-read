# 开屏与图标设计（1.3.0）

主题：翻开一本书，进入樱花下的阅读时光。开屏约 1.5 秒，书页向两侧展开，立绘及标题渐显，花瓣飘落后进入书架。插画继承桌宠粉发、紫眼、白色花饰和服装特征；标题由程序绘制，避免图片内文字变形。图标以书页与樱花传达阅读主题，适配 Android 自适应图标和系统主题单色图标。

素材使用内置 imagegen 生成，提示词：

- 开屏：portrait mobile reader app splash, same long pastel pink hair, purple eyes, small white daisy on viewer right, cream cardigan, burgundy ribbon and navy skirt; polished anime illustration, seated reading an open book under sakura branches, drifting pages and petals, blush pink, ivory and muted lilac, character and book in lower middle, negative space in top quarter, no text, logos or watermarks.
- 图标：Android reading app launcher icon, recognizable open cream-white book with pages forming sakura petals and a pink blossom above the spine, soft rose pink and lavender gradient, clean premium Japanese literary stationery, centered composition, no text, watermark or characters.

重新生成 Android 图标：安装 Pillow 后运行 `python tool/make_icon.py`。

## 1.4.4 图标更新

桌面图标改为桌宠抱书阅读，沿用粉发、紫眼、白色花饰及服装；Android 主题图标同步改为桌宠与书的单色轮廓。新图标由内置 imagegen 参考 `assets/images/pet_chibi.png` 生成，提示词：square Android launcher icon, same chibi mascot with long pastel pink hair, big violet eyes, white daisy hairpin on viewer right, cream cardigan, burgundy ribbon and navy skirt, happily reading an open book, crisp anime chibi, pink lavender background, centered safe area, no text, frame or watermark.
