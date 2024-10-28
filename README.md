首先装好 Linux 系统，推荐 Ubuntu LTS  

安装编译依赖  
sudo apt update -y  
sudo apt full-upgrade -y  
sudo apt install -y dos2unix libfuse-dev  
sudo bash -c 'bash <(curl -sL https://build-scripts.immortalwrt.org/init_build_environment.sh)'  

使用步骤：  
git clone https://github.com/ZqinKing/wrt_relese.git  
cd wrt_relese  
  
编译京东云雅典娜、亚瑟:  
./build.sh jdc_ax1800pro-ax6600_libwrt  

编译红米AX6000:  
./build.sh redmi_ax6000_immwrt21  

编译京东云百里:   
./build.sh jdc_ax6000_imm23
