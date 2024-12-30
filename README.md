首先装好 Linux 系统，推荐 Ubuntu LTS  

安装编译依赖  
sudo apt -y update  
sudo apt -y full-upgrade  
sudo apt install -y dos2unix libfuse-dev  
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'  

使用步骤：  
git clone https://github.com/ZqinKing/wrt_relese.git  
cd wrt_relese  
  
编译京东云雅典娜、亚瑟、太乙:  
./build.sh jdcloud_ipq60xx_libwrt  

编译红米AX6000:  
./build.sh redmi_ax6000_immwrt21  

编译京东云百里:   
./build.sh jdcloud_ax6000_immwrt23
  
编译红米AX5:  
./build.sh redmi_ax5_libwrt  

编译CMCC RAX3000M:  
./build.sh cmcc_rax3000m_immwrt21  
  
三方插件源自：https://github.com/kenzok8/small-package.git  
  