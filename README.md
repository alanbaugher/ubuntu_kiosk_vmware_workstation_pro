# ubuntu_kiosk_vmware_workstation_pro
A bootable USB Flash drive using Ubuntu OS that will auto install VMware Workstation Pro 25H2 and extact a VMware Image.  

<img width="1720" height="1019" alt="image" src="https://github.com/user-attachments/assets/ea7e49a1-275c-4dd4-894b-89393c02388c" />  

<img width="1979" height="972" alt="image" src="https://github.com/user-attachments/assets/1a5afc17-3481-4fe0-b761-0234ab66b7fb" />  

<img width="1790" height="1046" alt="image" src="https://github.com/user-attachments/assets/71c7ff50-de1b-486b-b849-2758a55c458e" />  


## View of the two (2) bootable files of "meta-data" and "user-data" -  "user-data" must be defined in YAML, UTF, and Unix LF format.  
<img width="1046" height="621" alt="image" src="https://github.com/user-attachments/assets/c8d17196-bb85-4004-98ba-61a598740a25" />  

## View of the two (2) bootable files of "grub.cfg" and "loopback.cfg"  -  These files reference the folder /autoinstaller, where "user-data" and "meta-data" resides.  
<img width="1019" height="613" alt="image" src="https://github.com/user-attachments/assets/dfa6de6d-302b-4d3e-a96a-f2412fa459dd" />  

##  View of the required two (2) post intallation files.  The first file "postinstall.sh" has minimal updates that will work correctly in a "chroot" environment.   The second file "postinstall2.sh" will be added to the context of the user account "ubuntu"  
<img width="1289" height="613" alt="image" src="https://github.com/user-attachments/assets/76c4a5b3-cb4b-405f-9a69-271bdb941aee" />  

## View of any required offline deb packages that will be installed immediately after the OS installation - does not require network connection.
<img width="1157" height="617" alt="image" src="https://github.com/user-attachments/assets/b1b06fb8-7f89-48bd-8956-a66fc3a80ce7" />  

## View of a compressed (7z) MS Windows 10 image spilt into 4GB files to accomidate the FAT32 format requirement for the Ubuntu Bootable ISO  
<img width="987" height="613" alt="image" src="https://github.com/user-attachments/assets/ba41cdb9-6461-4731-a24c-8c521e48bf11" />  




