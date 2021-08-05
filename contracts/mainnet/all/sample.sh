# https://stackoverflow.com/questions/414164/how-can-i-select-random-files-from-a-directory-in-bash/46234516
ls |sort -R |tail -4500 |while read file; do
    cp $file sample4500/$file
    # Something involving $file, or you can leave
    # off the while to just get the filenames
done
