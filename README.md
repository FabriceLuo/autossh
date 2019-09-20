# autossh
实现ssh自动密码登录

## 特性
- [x] 密码保存，保存成功登录的主机、用户名、密码，实现下次的自动登录
- [x] 部分密码输入，根据特定规则，生成登录密码，减少输入错误
- [x] 部分密码库，将常用部分密码存储，实现密码自动生成及登录失败重试
- [x] 密码自动更新，当旧密码登录失败后，用新密码替换旧密码
- [ ] 自动免密码登录，登录成功后同步ssh公钥，下次直接使用私钥登录
- [ ] 部分密码库自动更新，当遇到新的部分密码时，加入到部分密码库中
- [x] 密码手动输入，当尝试所有可能的密码失败后，用户输入密码，成功后保存
- [x] 主机模糊匹配，根据输入对已保存的主机进行匹配，提高输入效率
- [ ] 针对部分密码，使用引用计数进行排序，提升匹配效率

## 基础
- 使用json作为数据存储，通过jq进行数据操作
- 使用sshpass实现密码ssh密码输入
- 使用shell脚本进行开发，整合已有工具
