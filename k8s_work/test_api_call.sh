#!/bin/bash

# 총 반복 횟수
ITERATIONS=100

echo "=== APIM 테스트 시작 ==="
echo "각 요청을 ${ITERATIONS}회 실행합니다."
echo ""

# 용인시관광사업체 1
echo "=== 용인시관광사업체 url 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
    echo "[$i/$ITERATIONS] 용인시관광사업체 url 요청 실행 중..."
    xh GET http://4.230.159.239/gateway/apim/openapi/url/test/yongintour service-key==7265d69d-3e93-4b17-b63e-c65f03eebb28 pageNo==1 numOfRows==10 > /dev/null 2>&1
done
echo "용인시관광사업체 url 요청 완료"
echo ""

# 용인시관광사업체 2
echo "=== 용인시관광사업체 db 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
    echo "[$i/$ITERATIONS] 용인시관광사업체 db 요청 실행 중..."
    xh GET http://4.230.159.239/gateway/apim/openapi/db/test/yongintourdb service-key==7265d69d-3e93-4b17-b63e-c65f03eebb28 > /dev/null 2>&1
done
echo "용인시관광사업체 db 요청 완료"
echo ""

# 용인시관광사업체 3
echo "=== 용인시관광사업체 query 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
    echo "[$i/$ITERATIONS] 용인시관광사업체 query 요청 실행 중..."
    xh GET http://4.230.159.239/gateway/apim/openapi/query/test/yongintourquery service-key==7265d69d-3e93-4b17-b63e-c65f03eebb28 > /dev/null 2>&1
done
echo "용인시관광사업체 query 요청 완료"
echo ""

# 용인시신간도서 1
echo "=== 용인시신간도서 url 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
    echo "[$i/$ITERATIONS] 용인시신간도서 url 요청 실행 중..."
    xh GET http://4.230.159.239/gateway/apim/openapi/url/test/yonginnewbookurl service-key==7265d69d-3e93-4b17-b63e-c65f03eebb28 > /dev/null 2>&1
done
echo "용인시신간도서 url 요청 완료"
echo ""

# 용인시신간도서 2
echo "=== 용인시신간도서 db 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
    echo "[$i/$ITERATIONS] 용인시신간도서 db 요청 실행 중..."
    xh GET http://4.230.159.239/gateway/apim/openapi/db/test/yonginnewbookdb service-key==7265d69d-3e93-4b17-b63e-c65f03eebb28 > /dev/null 2>&1
done
echo "용인시신간도서 db 요청 완료"
echo ""

# 용인시신간도서 3
echo "=== 용인시신간도서 query 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
    echo "[$i/$ITERATIONS] 용인시신간도서 query 요청 실행 중..."
    xh GET http://4.230.159.239/gateway/apim/openapi/query/test/yonginnewbookquery service-key==7265d69d-3e93-4b17-b63e-c65f03eebb28 > /dev/null 2>&1
done
echo "용인시신간도서 query 요청 완료"
echo ""

# 용인시신간도서 4
echo "=== 용인시신간도서 query loan_yn=Y 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
    echo "[$i/$ITERATIONS] 용인시신간도서 query loan_yn=Y 요청 실행 중..."
    xh GET http://4.230.159.239/gateway/apim/openapi/query/test/yonginnewbookquery service-key==7265d69d-3e93-4b17-b63e-c65f03eebb28 loan_yn==Y > /dev/null 2>&1
done
echo "용인시신간도서 query loan_yn=Y 요청 완료"
echo ""

# 용인시신간도서 5
echo "=== 용인시신간도서 query loan_yn=N 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
    echo "[$i/$ITERATIONS] 용인시신간도서 query loan_yn=N 요청 실행 중..."
    xh GET http://4.230.159.239/gateway/apim/openapi/query/test/yonginnewbookquery service-key==7265d69d-3e93-4b17-b63e-c65f03eebb28 loan_yn==N > /dev/null 2>&1
done
echo "용인시신간도서 query loan_yn=N 요청 완료"
echo ""

echo "=== 모든 테스트 완료 ==="

