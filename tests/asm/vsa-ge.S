mov $0, %ecx

loop:

inc %ecx
cmp $20, %ecx
jge loop

done:
hlt
