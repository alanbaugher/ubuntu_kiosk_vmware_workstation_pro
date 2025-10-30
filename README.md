# ubuntu_kiosk_vmware_workstation_pro
A bootable USB Flash drive using Ubuntu OS that will auto install VMware Workstation Pro 25H2 and extact a VMware Image.  

<img width="1920" height="1080" alt="image" src="https://github.com/user-attachments/assets/3d518f3d-eb77-40a2-b70f-200b2eef48a3" />  

Duration:  
10-15 min for OS installation on HDD/SDD of workstation with copy of all media files and installation of offline deb package files.  
10-30 min for 1st reboot into the user's desktop where the process will perform a VMware Workstation Pro installation, extract of VMware Image, and update of Gnome/Desktop Links with prompt for a final reboot.  
2-5 min after 2nd reboot, the solution should auto-authenticate into the user's desktop and then auto-start any VMware image that was deployed.  

  

## View of the architecture model for building and utilization of the custom ISO.    
<img width="1720" height="1019" alt="image" src="https://github.com/user-attachments/assets/ea7e49a1-275c-4dd4-894b-89393c02388c" />  
  
## View of the processes used for building the custom ISO.    
<img width="1979" height="972" alt="image" src="https://github.com/user-attachments/assets/1a5afc17-3481-4fe0-b761-0234ab66b7fb" />  

## View of the custom bootable configuration files within the custom ISO and their integration with each other.    
<img width="1790" height="1046" alt="image" src="https://github.com/user-attachments/assets/71c7ff50-de1b-486b-b849-2758a55c458e" />  


## View of the two (2) bootable files of "meta-data" and "user-data" -  "user-data" must be defined in YAML, UTF8, and Unix LF encoding/format.  
<img width="1046" height="621" alt="image" src="https://github.com/user-attachments/assets/c8d17196-bb85-4004-98ba-61a598740a25" />  

## View of the two (2) bootable files of "grub.cfg" and "loopback.cfg"  -  These files reference the folder /autoinstaller, where "user-data" and "meta-data" resides.  
<img width="1019" height="613" alt="image" src="https://github.com/user-attachments/assets/dfa6de6d-302b-4d3e-a96a-f2412fa459dd" />  

## View of the required two (2) post installation files.  The first file "postinstall.sh" has minimal updates that will work correctly in a "chroot" environment.   The second file "postinstall2.sh" will be added run in the context of the user account "ubuntu"  
<img width="1289" height="613" alt="image" src="https://github.com/user-attachments/assets/76c4a5b3-cb4b-405f-9a69-271bdb941aee" />  

## View of any required offline debian (deb) packages that will be installed immediately after the OS installation - does not require network connection.
<img width="1157" height="617" alt="image" src="https://github.com/user-attachments/assets/b1b06fb8-7f89-48bd-8956-a66fc3a80ce7" />  

## View of a compressed (7z) MS Windows 10 image spilt into 4GB files to accomidate the FAT32 format requirement for the Ubuntu Bootable ISO  
<img width="987" height="613" alt="image" src="https://github.com/user-attachments/assets/ba41cdb9-6461-4731-a24c-8c521e48bf11" />  


## Follow up notes:
Download the latest Linux VMware Workstation Pro binary for Linux from Broadcom Support Site under Free Software Downloads.  
https://support.broadcom.com/group/ecx/productfiles?subFamily=VMware%20Workstation%20Pro&displayGroup=VMware%20Workstation%20Pro%2025H2%20for%20Linux&release=25H2&os=&servicePk=&language=EN&freeDownloads=true  

<img width="913" height="250" alt="image" src="https://github.com/user-attachments/assets/931b0cea-90bf-4868-8246-8a87dcadc63e" />  
<img width="1404" height="541" alt="image" src="https://github.com/user-attachments/assets/9a679d21-94d5-402a-aabc-fddb0b564c18" />  
<img width="1075" height="921" alt="image" src="https://github.com/user-attachments/assets/38222e97-d3fc-4e99-b94d-4fd5a440ab14" />  
<img width="2130" height="922" alt="image" src="https://github.com/user-attachments/assets/7e76a80b-9a50-48e6-ad25-04034f79d118" />  


Ubuntu Desktop ISO:  
<img width="257" height="195" alt="image" src="https://github.com/user-attachments/assets/4dd2271f-9f68-4f59-a74b-ca6302c66a99" />  
https://ubuntu.com/download/desktop  

For editing the standard Ubuntu ISO, select an ISO editor tool such as UltraISO or WinISO or similar.   
Note:  The size of the ISO will required the paid versions of these editor tools.  
https://www.ultraiso.com/  
  
To burn the ISO to USB Flash Driver, recommend using Rufus.  
<img width="811" height="253" alt="image" src="https://github.com/user-attachments/assets/fa47a934-0ded-464b-a66d-566fcec6ed74" />  
https://rufus.ie/en/   













