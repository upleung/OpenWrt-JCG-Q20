**最重要的一句话：**  
通常项目里，**img（图片）放在 `assets/` 或 `public/` 下的 `images/` 子目录；docs（文档）放在仓库根目录的 `docs/` 文件夹。**  
这是 GitHub、前端、后端、开源项目最通用的标准结构。  [Github](https://github.com/kriasoft/Folder-Structure-Conventions)

下面给你一个专业级、可直接复制到你项目里的结构方案。

---

# ✅ 标准专业项目结构（适用于前端/后端/开源项目）

```
project-root/
│
├── src/                # 源代码（核心逻辑）
│
├── public/             # 静态资源（前端项目常用）
│   └── images/         # 图片（logo、banner、图标）
│
├── assets/             # 资源文件（后端/工具类项目常用）
│   ├── images/         # 图片
│   ├── fonts/          # 字体
│   └── icons/          # 图标
│
├── docs/               # 文档（说明书、设计文档、API 文档）
│   ├── architecture.md
│   ├── api.md
│   └── changelog.md
│
├── test/               # 自动化测试
│
├── tools/              # 工具脚本
│
├── README.md           # 项目说明
└── LICENSE
```

这个结构来自 GitHub 官方推荐的项目布局示例（如 `build/`, `docs/`, `src/`, `test/`）  [Github](https://github.com/kriasoft/Folder-Structure-Conventions)  
并结合现代代码组织最佳实践（如将静态资源放在 `assets/` 或 `public/`）  [GeeksForGeeks](https://www.geeksforgeeks.org/javascript/file-and-folder-organization-best-practices-for-web-development/)。

---

# 📁 图片 img 应该放哪里？

## **前端项目（React / Vue / Next.js / Vite）**
推荐：

```
public/images/
src/assets/images/
```

理由：

- `public/` 下的图片可直接通过 URL 访问（适合 logo、favicon）
- `src/assets/images/` 适合组件内部引用（打包优化）

---

## **后端项目（Node.js / Python / Go）**
推荐：

```
assets/images/
```

理由：

- 后端不会直接暴露静态资源，通常由 Nginx 或前端处理
- `assets/` 是后端项目通用的资源目录（GitHub 多个项目采用此结构）  [Github](https://github.com/kriasoft/Folder-Structure-Conventions)

---

## **工具类 / CLI / 库项目**
推荐：

```
assets/
```

例如：

```
assets/logo.png
assets/templates/
```

---

# 📁 文档 docs 应该放哪里？

标准答案：

```
docs/
```

这是 GitHub 官方推荐的文档目录结构（如 `docs/faq.md`, `docs/misc.md`）  [Github](https://github.com/kriasoft/Folder-Structure-Conventions)。

适合放：

- API 文档
- 架构设计
- 使用说明
- 版本变更日志
- 设计图（可以放 docs/images/）

示例：

```
docs/
├── api/
│   └── v1.md
├── architecture/
│   └── overview.md
├── images/
│   └── system-diagram.png
└── changelog.md
```

---

# 🧭 为什么图片不放 docs/？

因为：

- docs 是文档目录，不适合放项目运行需要的图片
- 图片属于静态资源，应放在 assets/public/images
- docs/images 只用于文档插图，不用于项目运行

---

# 🧭 为什么不把图片放在 src/？

因为：

- src 是代码目录，放图片会导致构建工具处理不一致
- 图片属于资源，不属于代码逻辑

现代最佳实践明确建议将静态资源放在 assets/public，而不是 src  [GeeksForGeeks](https://www.geeksforgeeks.org/javascript/file-and-folder-organization-best-practices-for-web-development/)。

---

# 🎯 最推荐的最终结构（你可以直接用）

适合你这种专业开发项目：

```
project/
│
├── src/
│
├── public/
│   └── images/          # 前端可直接访问的图片
│
├── assets/
│   ├── images/          # 项目内部使用的图片
│   └── icons/
│
├── docs/
│   ├── api/
│   ├── architecture/
│   └── images/          # 文档插图
│
├── test/
│
├── tools/
│
├── README.md
└── LICENSE
```

---

# 📌 给你一个判断表（非常实用）

| 文件类型 | 推荐目录 | 用途 |
|---------|----------|------|
| 项目运行需要的图片 | `assets/images/` | 代码引用 |
| 前端页面展示图片 | `public/images/` | URL 访问 |
| 文档插图 | `docs/images/` | 文档说明 |
| 文档（Markdown） | `docs/` | API、架构、说明书 |
| 代码 | `src/` | 主逻辑 |
| 测试 | `test/` | 自动化测试 |

---
