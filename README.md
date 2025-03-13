首先安装 Linux 系统，推荐 Ubuntu LTS  

安装编译依赖  
sudo apt -y update  
sudo apt -y full-upgrade  
sudo apt install -y dos2unix libfuse-dev  
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'  

使用步骤：  
git clone https://github.com/ZqinKing/wrt_release.git  
cd wrt_relese  
  
编译京东云雅典娜(02)、亚瑟(01)、太乙(07)、AX5(JDC版):  
./build.sh jdcloud_ipq60xx_immwrt  
./build.sh jdcloud_ipq60xx_libwrt  
  
编译京东云百里:  
./build.sh jdcloud_ax6000_immwrt  
  
编译阿里云AP8220:  
./build.sh aliyun_ap8220_immwrt  
  
编译红米AX5:  
./build.sh redmi_ax5_immwrt  
  
编译红米AX6:  
./build.sh redmi_ax6_immwrt  
  
编译红米AX6000:  
./build.sh redmi_ax6000_immwrt21  
  
编译CMCC RAX3000M:  
./build.sh cmcc_rax3000m_immwrt  
  
编译N1:  
./build.sh n1_immwrt  
  
编译X64:  
./build.sh x64_immwrt  
  
编译兆能M2:  
./build.sh zn_m2_immwrt  
./build.sh zn_m2_libwrt  
  
三方插件源自：https://github.com/kenzok8/small-package.git  
  
使用OAF（应用过滤）功能前，需先完成以下操作：  
1. 打开系统设置 → 启动项 → 定位到「appfilter」  
2. 将「appfilter」当前状态**从已禁用更改为已启用**  
3. 完成配置后，点击**启动**按钮激活服务  