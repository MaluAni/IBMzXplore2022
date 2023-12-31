#!/bin/env bash
#create control dir and copy control dataset 
mkdir ~/control
mkdir -p ~/control/mea
scp -r "//'$1'" ~/control/control
CONTROL=~/control/control
MEA=~/control/mea
#get pass from setings file
PassWord=`grep -e "password" ~/.zowe/profiles/zosmf/IBMZXplore.yaml | cut -d ":" -f 2 | cut -d " " -f 2`
#create variables from control file
dsn=`head -1 "$CONTROL" | tr '[:upper:]' '[:lower:]' | cut -d '=' -f 2 | cut -d ' ' -f 1`
dsn_upper=`head -1 "$CONTROL" | cut -d '=' -f 2 | cut -d ' ' -f 1`
data=`head -5 "$CONTROL" | tail -1 | cut -d '(' -f 2 | cut -d ')' -f 1`
results=$(grep -e "RESULTS=DSN" "$CONTROL" | cut -d"(" -f2 | cut -d"(" -f1)

zowe zos-files create data-set-partitioned "$USER"."$results" --dst LIBRARY
echo "connect to 204.90.115.200:5040/DALLASC user $USER using ********;" | tee "$MEA"/temp.sql
schema=`grep -e "STKDATA" "$CONTROL" | cut -d '(' -f 2 | cut -d '.' -f 1`
echo "connect to 204.90.115.200:5040/DALLASC user $USER using ********;" | tee "$MEA"/temp1.sql
echo "connect to 204.90.115.200:5040/DALLASC user $USER using ********;" | tee "$MEA"/temp2.sql
#create MEA part
scp -r "//'$dsn.$data'" $MEA
cp "//'$dsn.MEA'" "$MEA"/code
meaenc=`head -1 "$MEA"/code`
maecode=$(echo $meaenc | openssl enc -d -a)
awk '{print $0 "$" FILENAME}' "$MEA"/@* >> "$MEA"/all1
grep -v 'id' "$MEA"/all1 >> "$MEA"/all
awk -F'$' '{print $5}' "$MEA"/all >> "$MEA"/all_enc
python -c '
import base64
f=open("'$MEA'/all_dec", "a")
file=open("'$MEA'/all_enc","r")
for line in file.readlines():
    f.write(base64.b64decode(line).decode()+"\n")
'

paste -d '$' "$MEA"/all "$MEA"/all_dec >> "$MEA"/all_encdec
grep -e "$maecode" "$MEA"/all_encdec >> "$MEA"/relevant
awk -F'$' '{print $6}' "$MEA"/relevant | cut -d '/' -f 6 >> "$MEA"/relevant_file
awk -F'$' '{ print $3 "," $2}' "$MEA"/relevant >> "$MEA"/final1
paste -d ',' "$MEA"/relevant_file "$MEA"/final1 >> "$MEA"/final2
sort -t, -nk2 "$MEA"/final2 >> "$MEA"/meafinal
meadest=`grep -e "MEARESULTS" "$CONTROL" | cut -d '=' -f 2 | cut -d ' ' -f 1`
zowe zos-files upload ftds "$MEA/meafinal" "$USER.$meadest"

#Create STK part

cp "//'$dsn.STK'" "$MEA"/stk_code
stkenc=`head -1 "$MEA"/stk_code`
stkcode=$(echo $stkenc | openssl enc -d -a)
echo "SELECT REMARKS
    FROM SYSIBM.SYSCOLUMNS
    where tbcreator = '$schema' and name='MAVAILABLE';" >> "$MEA"/temp1.sql
cat "$MEA"/temp1.sql
java com.ibm.db2.clp.db2 -tvxf "$MEA"/temp1.sql -z "$MEA"/stkdecrypt
PassCodeSTK=`grep -e "key:" "$MEA"/stkdecrypt | cut -d ':' -f 2 | cut -d ' ' -f 1`
cp "//'$dsn.STK'" "$MEA"/STKcode
stkenc=`head -1 "$MEA"/STKcode`
stkcode=$(echo $stkenc | openssl enc -d -a)
echo "SELECT V.PCODE, E.MCODE, L.PQUANTITY, E.MNAME, DECRYPT_CHAR(A.MAVAILABLE, '$PassCodeSTK')
    FROM ZXP422.STKPART V
    INNER JOIN ZXP422.STKMAN E
      ON V.MID = E.MID
    INNER JOIN ZXP422.STKLVL L
       ON V.PID = L.PID    
    INNER JOIN ZXP422.STKAVAIL A
       ON V.MID = A.MID
    where V.PNAME like '%$stkcode%'
    ORDER BY V.PCODE;" >> "$MEA"/temp2.sql
java com.ibm.db2.clp.db2 -tvxf "$MEA"/temp2.sql -z "$MEA"/stkdb2
grep -e "YES" "$MEA"/stkdb2>> "$MEA"/stkYES
awk -F' ' '{ print $1 "," $2 "," $3 "," $4}' "$MEA"/stkYES | sed 's/ //g' >> "$MEA"/stkfinal1
sort -t, -k1 "$MEA"/stkfinal1 >> "$MEA"/stkfinal
stkdest=`grep -e "STKRESULTS" "$CONTROL" | cut -d '=' -f 2 | cut -d ' ' -f 1`
zowe zos-files upload ftds "$MEA/stkfinal" "$USER.$stkdest"

#Create GSK part

cp "//'$dsn.GSK'" "$MEA"/GSKcode
gskenc=`head -1 "$MEA"/GSKcode`
gskcode=$(echo $gskenc | openssl enc -d -a)
gskdata=`grep -e "GSKDATA" "$CONTROL" | cut -d '(' -f 2 | cut -d ')' -f 1`
gskres=`grep -e "GSKRESULTS" "$CONTROL" | cut -d '=' -f 2 | cut -d ' ' -f 1`
for file in "$gskdata".master/.vendors/.*; do    
    grep -e "$gskcode" "$file" /dev/null >> "$MEA"/gsk_vendors
    done
cat "$MEA"/gsk_vendors | cut -d '.' -f 4 | cut -d ':' -f 1 | sort -u >> "$MEA"/gsk_vendors_relevant_enc
cat "$MEA"/gsk_vendors_relevant_enc
python -c '
rot13=str.maketrans("ABCDEFGHIJKLMabcdefghijklmNOPQRSTUVWXYZnopqrstuvwxyz","NOPQRSTUVWXYZnopqrstuvwxyzABCDEFGHIJKLMabcdefghijklm")
f=open("'$MEA'/gsk_vendors_relevant", "a")
file=open("'$MEA'/gsk_vendors_relevant_enc","r")
for line in file.readlines():
    f.write(line.translate(rot13))
'
cat "$MEA"/gsk_vendors_relevant
awk -F':' '{ print $2 ":" $3 }' "$MEA"/gsk_vendors | sort -t: -k1 >> "$MEA"/gsk_part1

while IFS= read -r line
    do
        cat "$gskdata".master/"$line" >> "$MEA"/gsk_transactions_all
    done < "$MEA"/gsk_vendors_relevant  
sort -r "$MEA"/gsk_transactions_all | head -5 | cut -d '/' -f 6 >> "$MEA"/gsk_transactions_top5
cat "$MEA"/gsk_transactions_top5
while IFS= read -r line
    do
        cat "$gskdata".master/.history/"$line" | sed 's/ //g' >> "$MEA"/gsk_transactions_top5_part2
    done < "$MEA"/gsk_transactions_top5
paste -d ':' "$MEA"/gsk_transactions_top5 "$MEA"/gsk_transactions_top5_part2 >> "$MEA"/gsk_transactions
cat "$MEA"/gsk_transactions >> "$MEA"/gsk_part1
cat "$MEA"/gsk_part1 
zowe zos-files upload ftds "$MEA/gsk_part1" "$USER.$gskres"

#Create GAS part

gas_product=`grep -e "GASDATA" "$CONTROL" | cut -d '(' -f 2 | cut -d ',' -f 1`
gas_vendor=`grep -e "GASDATA" "$CONTROL" | cut -d '(' -f 2 | cut -d ',' -f 2`
gas_prodproc=`grep -e "GASDATA" "$CONTROL" | cut -d '(' -f 2 | cut -d ',' -f 3`
gas_proc=`grep -e "GASDATA" "$CONTROL" | cut -d '(' -f 2 | cut -d ',' -f 4 | cut -d ')' -f 1`
gasres=`grep -e "GASRESULTS" "$CONTROL" | cut -d '=' -f 2 | cut -d ' ' -f 1`
rm "$MEA"/repro_vendor
rm "$MEA"/gas_vendor
touch "$MEA"/gas_vendor
rm "$MEA"/gas_prodproc
touch "$MEA"/gas_prodproc
rm "$MEA"/gas_product
touch "$MEA"/gas_product
echo '//REPROGAS   JOB  REPROJCL
//IDCAMS1   EXEC PGM=IDCAMS
//SYSPRINT DD   SYSOUT=A
//OUTPUT   DD   DSNAME=&SYSUID..CONTEST.GAS.VENDOR,DISP=(NEW,CATLG),   
//     UNIT=SYSALLDA,SPACE=(TRK,1),RECFM=VB,LRECL=3000          
//SYSIN    DD   *,SYMBOLS=EXECSYS
     
     REPRO -
            INDATASET('$dsn_upper'.'$gas_vendor') -            
            OUTFILE(OUTPUT)
//COPYFIL1 EXEC PGM=IKJEFT01
//IN DD DISP=SHR,DSN=&SYSUID..CONTEST.GAS.VENDOR
//OUT DD PATH='\''/z/z02566/control/mea/gas_vendor'\''
//SYSTSPRT DD SYSOUT=*
//SYSTSIN DD *
    OCOPY INDD(IN) OUTDD(OUT) TEXT
//IDCAMS2   EXEC PGM=IDCAMS
//SYSPRINT DD   SYSOUT=A
//OUTPUT   DD   DSNAME=&SYSUID..CONTEST.GAS.PRODPROC,DISP=(NEW,CATLG),   
//     UNIT=SYSALLDA,SPACE=(TRK,1),RECFM=VB,LRECL=3000          
//SYSIN    DD   *,SYMBOLS=EXECSYS
     
     REPRO -
            INDATASET('$dsn_upper'.'$gas_prodproc') -            
            OUTFILE(OUTPUT)
//COPYFIL2 EXEC PGM=IKJEFT01
//IN DD DISP=SHR,DSN=&SYSUID..CONTEST.GAS.PRODPROC
//OUT DD PATH='\''/z/z02566/control/mea/gas_prodproc'\''
//SYSTSPRT DD SYSOUT=*
//SYSTSIN DD *
    OCOPY INDD(IN) OUTDD(OUT) TEXT
//IDCAMS3   EXEC PGM=IDCAMS
//SYSPRINT DD   SYSOUT=A
//OUTPUT   DD   DSNAME=&SYSUID..CONTEST.GAS.PRODUCT,DISP=(NEW,CATLG),   
//     UNIT=SYSALLDA,SPACE=(TRK,1),RECFM=VB,LRECL=3000          
//SYSIN    DD   *,SYMBOLS=EXECSYS
     
     REPRO -
            INDATASET('$dsn_upper'.'$gas_product') -            
            OUTFILE(OUTPUT)
//COPYFIL3 EXEC PGM=IKJEFT01
//IN DD DISP=SHR,DSN=&SYSUID..CONTEST.GAS.PRODUCT
//OUT DD PATH='\''/z/z02566/control/mea/gas_product'\''
//SYSTSPRT DD SYSOUT=*
//SYSTSIN DD *
    OCOPY INDD(IN) OUTDD(OUT) TEXT    
/*' >> "$MEA"/repro_vendor
zowe zos-jobs submit local-file "$MEA"/repro_vendor -d "$MEA"
scp -r "//'$dsn.$gas_proc'" "$MEA"/gas_proc
zowe zos-files download data-set $USER.CONTEST.GAS.PRODPROC -f "$MEA"/gas_prodproc1
awk -F'*' '{ print $2 }' "$MEA"/gas_prodproc1 >> "$MEA"/gas_prod_enc
python -c '
import base64
f=open("'$MEA'/gas_prod_dec1", "a")
file=open("'$MEA'/gas_prod_enc","r")
for line in file.readlines():
    f.write(base64.b64decode(line).decode()+"\n")
'
awk -F'--' '{ print $1 }' "$MEA"/gas_prod_dec1 >> "$MEA"/gas_prod_dec
sed 's/*/,/g' "$MEA"/gas_prodproc1 >> "$MEA"/gas_prodproc2
paste -d ',' "$MEA"/gas_prodproc2 "$MEA"/gas_prod_dec >> "$MEA"/gas_prod_dec_added
sort -r -t, -nk3 "$MEA"/gas_vendor >> "$MEA"/gas_vendor_sorted

tail -n +2 "$MEA"/gas_proc >> "$MEA"/proc_no_header
sort -t, -nk2 "$MEA"/proc_no_header >> "$MEA"/proc_no_header_sorted
bestproc=`head -1 "$MEA"/proc_no_header_sorted | cut -d"," -f1`
bestprocval=`head -1 "$MEA"/proc_no_header_sorted | cut -d"," -f2`

cut -f3 -d',' "$MEA"/gas_vendor_sorted | sort -r | uniq -c >> "$MEA"/gas_vendor_sorted_count
gasprocmax=`head -1 "$MEA"/gas_vendor_sorted_count | cut -d' ' -f5`
gasprocmaxcount=`head -1 "$MEA"/gas_vendor_sorted_count | cut -d' ' -f4`
head -$gasprocmaxcount "$MEA"/gas_vendor_sorted >> "$MEA"/gas_vendor_best

grep -e $bestproc "$MEA"/gas_prod_dec_added >> "$MEA"/gas_prod_best_proc1
cut -d"," -f1 "$MEA"/gas_prod_best_proc1 >> "$MEA"/gas_prod_best_proc
cut -d"," -f1 "$MEA"/gas_vendor_best >> "$MEA"/gas_vendor_best_codes
grep -f "$MEA"/gas_vendor_best_codes "$MEA"/gas_product >> "$MEA"/gas_product_best_vendors
grep -f "$MEA"/gas_prod_best_proc "$MEA"/gas_product_best_vendors >> "$MEA"/gas_product_best_vendors_proc 
cut -d"*" -f1,4,5 "$MEA"/gas_product_best_vendors_proc | head -3 >> "$MEA"/gas_product_best_vendors_proc_top3
cut -d"*" -f3 "$MEA"/gas_product_best_vendors_proc_top3 >> "$MEA"/gas_product_best_vendors_proc_top3_codes
tr -d '\r' < "$MEA"/gas_product_best_vendors_proc_top3_codes  >> "$MEA"/gas_product_best_vendors_proc_top3_codes1

while IFS= read -r line
    do
        
        grep "$line" "$MEA"/gas_vendor_best | cut -f2 -d"," >> "$MEA"/gas_product_best_vendors_proc_top3_names
                
    done < "$MEA"/gas_product_best_vendors_proc_top3_codes1
#grep -f "$MEA"/gas_product_best_vendors_proc_top3_codes1 "$MEA"/gas_vendor_best | cut -f2 -d"," >> "$MEA"/gas_product_best_vendors_proc_top3_names

tr -d '\r' < "$MEA"/gas_product_best_vendors_proc_top3 >> "$MEA"/gas_product_best_vendors_proc_top3_1
paste -d '*' "$MEA"/gas_product_best_vendors_proc_top3_1 "$MEA"/gas_product_best_vendors_proc_top3_names >> "$MEA"/gas_concat1

cat "$MEA"/gas_concat1 | sed 's/*/,/g' >> "$MEA"/gas_concat

awk -F"," '{print '$bestprocval' "," $1 "," $3 "\n@" "'$bestproc'" "@" '$gasprocmax' "@" $4}' "$MEA"/gas_concat >> "$MEA"/gas_final_test
zowe zos-files upload ftds "$MEA/gas_final_test" "$USER.$gasres"
zowe zos-files delete data-set $USER.CONTEST.GAS.PRODUCT -f
zowe zos-files delete data-set $USER.CONTEST.GAS.PRODPROC -f
zowe zos-files delete data-set $USER.CONTEST.GAS.VENDOR -f

#Create ASM part

awk -F'$' '{ print $3 }' "$MEA"/relevant >> "$MEA"/codes
#needs grep from control with ASM URL - current is hardcoded as http://192.86.32.12:1880/Q4Y22FINAL/ 
while IFS= read -r line
    do
        curl -w "\r" "http://192.86.32.12:1880/Q4Y22FINAL/$line" | tr -d '\n' | grep -v '"status":"fail"' >> "$MEA"/asm_idcode
                
    done < "$MEA"/codes 
 
awk -F'"set":"' '{print $2}' "$MEA"/asm_idcode | sed 's/"}//g'>> "$MEA"/set
set=`head -1 "$MEA"/set | tr -d '\r'`
curl http://192.86.32.12:1880/Q4Y22FINAL/STK/$set >> "$MEA"/stk
curl http://192.86.32.12:1880/Q4Y22FINAL/GAS/$set >> "$MEA"/gas
curl http://192.86.32.12:1880/Q4Y22FINAL/GSK/$set >> "$MEA"/gsk

stk=`head -1 "$MEA"/stk | cut -d ',' -f 3 | cut -d '"' -f 4`
gas=`head -1 "$MEA"/gas | cut -d ',' -f 3 | cut -d '"' -f 4`
gsk=`head -1 "$MEA"/gsk | cut -d ',' -f 3 | cut -d '"' -f 4`

echo "SELECT V.PCODE, E.MCODE, E.MNAME
    FROM $schema.STKPART V
    INNER JOIN $schema.STKMAN E
      ON V.MID = E.MID    
    where V.PCODE like '%$stk%';" >> "$MEA"/temp.sql
java com.ibm.db2.clp.db2 -tvxf "$MEA"/temp.sql -z "$MEA"/stkdetails
grep -e "$stk" "$MEA"/stkdetails >> "$MEA"/stkdet
head -2 "$MEA"/stkdet | tail -1 | tr -d '\r' >> "$MEA"/stkdet2
stk_man_code=`head -2 "$MEA"/stkdet | cut -d ' ' -f 2` 
stk_man_name_enc=`head -2 "$MEA"/stkdet | cut -d ' ' -f 3`
stk_man_name_dec=$(echo $stk_man_name_enc | openssl enc -d -a)
stk_quantity=`head -1 "$MEA"/stk | cut -d ',' -f 4 | cut -d ':' -f 2`
JSON_STRING='{type:"'"STK"'",\nname:"'"$stk_man_name_dec"'",\nmanufacturer:"'"$stk_man_code"'",\ncode:"'"$stk"'",\nquantity:'$stk_quantity',\nset:"'"$set"'"\n},'
echo -e $JSON_STRING >> "$MEA"/stkjson
asm_idcode_name=`head -1 "$MEA"/asm_idcode | cut -d ',' -f 3 | cut -d ':' -f 2 | cut -d '"' -f 2`
asm_idcode_manufacturer=`head -1 "$MEA"/asm_idcode | cut -d ',' -f 4 | cut -d ':' -f 2 | cut -d '"' -f 2`
asm_idcode_code=`head -1 "$MEA"/asm_idcode | cut -d ',' -f 5 | cut -d ':' -f 2 | cut -d '"' -f 2`
asm_idcode_quantity=`head -1 "$MEA"/asm_idcode | cut -d ',' -f 6 | cut -d ':' -f 2`
JSON_STRING_MEA='[{type:"'"MEA"'",\nname:"'"$asm_idcode_name"'",\nmanufacturer:"'"$asm_idcode_manufacturer"'",\ncode:"'"$asm_idcode_code"'",\nquantity:'$asm_idcode_quantity',\nset:"'"$set"'"\n},'
echo -e $JSON_STRING_MEA >> "$MEA"/asm_final 
echo -e $JSON_STRING >> "$MEA"/asm_final

for file in "$gskdata".master/.vendors/.*; do    
    grep -e "$gsk" "$file" /dev/null >> "$MEA"/gskdata
    done

gskname=`head -1 "$MEA"/gskdata | cut -d ':' -f 3`
#gskmanufacturer=`head -1 "$MEA"/gskdata | cut -d ':' -f 1 | cut -d '.' -f 4`
gskquantity=`head -1 "$MEA"/gsk | cut -d ',' -f 4 | cut -d ':' -f 2`
JSON_STRING_GSK='{type:"'"GSK"'",\nname:"'"$gskname"'",\nmanufacturer:"'""'",\ncode:"'"$gsk"'",\nquantity:'$gskquantity',\nset:"'"$set"'"\n},'
echo -e $JSON_STRING_GSK >> "$MEA"/asm_final

tr -d '\r' < "$MEA"/gas_product >> "$MEA"/gas_product_nocarriage
gas_manufacturer=`grep -e $gas "$MEA"/gas_product_nocarriage | cut -d '*' -f 5 `
gas_name=`awk -F "$gas_manufacturer" '{print $2}' "$MEA"/gas_vendor | cut -d ',' -f 2 `
gas_quantity=`head -1 "$MEA"/gas | cut -d ',' -f 4 | cut -d ':' -f 2`
JSON_STRING_GAS='{type:"'"GAS"'",\nname:"'"$gas_name"'",\nmanufacturer:"'"$gas_manufacturer"'",\ncode:"'"$gas"'",\nquantity:'$gas_quantity',\nset:"'"$set"'"\n}]'

echo -e $JSON_STRING_GAS >> "$MEA"/asm_final
finaldata=`grep -e "ASMRESULTS" "$CONTROL" | cut -d '=' -f 2 | cut -d ' ' -f 1`
zowe zos-files upload ftds "$MEA/asm_final" "$USER.$finaldata"
reportdir=$(grep -e "REPORT" "$CONTROL" | cut -d"(" -f2 | cut -d")" -f1 | cut -d"/" -f2,3)
reportfile=$(grep -e "REPORT" "$CONTROL" | cut -d"(" -f2 | cut -d")" -f1 | cut -d"/" -f4)
echo $reportdir $reportfile
cd ~
mkdir -p $reportdir
touch $reportdir/$reportfile
ls -a $reportdir
cp ~/report22/q4y22.md $reportdir/$reportfile
rm -r ~/control
