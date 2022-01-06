#!/bin/bash

cd tmp_receive
nc -l -p 8081 > receive.tar.xz
tar Jxvf receive.tar.xz
rm receive.tar.xz
cd ..
