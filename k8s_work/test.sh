#!/usr/bin/env bash

# 총 반복 횟수
ITERATIONS=100

# 서비스 키 (비어있으면 파라미터에 포함되지 않음)
SERVICE_KEY=""
# SERVICE_KEY="3e6626b1-1582-40a7-8c87-ec058437c0d8"

# 서비스 키 파라미터 생성 (값이 있을 때만)
SERVICE_KEY_PARAM=""
[[ -n "$SERVICE_KEY" ]] && SERVICE_KEY_PARAM="service-key==$SERVICE_KEY"

echo "=== APIM 테스트 시작 ==="
echo "각 요청을 ${ITERATIONS}회 실행합니다."
echo ""

# 용인시관광사업체 1
URL="http://4.230.159.239/gateway/apim/openapi/db/test/yongintourdb"
PARAMS="$SERVICE_KEY_PARAM"
echo "=== 용인시관광사업체 db 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
  echo "[$i/$ITERATIONS] 용인시관광사업체 db 요청 실행 중... $URL $PARAMS"
  xh GET $URL $PARAMS >/dev/null 2>&1
done
echo "용인시관광사업체 db 요청 완료"
echo ""

# 용인시관광사업체 2
URL="http://4.230.159.239/gateway/apim/openapi/query/test/yongintourquery"
PARAMS="$SERVICE_KEY_PARAM"
echo "=== 용인시관광사업체 query 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
  echo "[$i/$ITERATIONS] 용인시관광사업체 query 요청 실행 중... $URL $PARAMS"
  xh GET $URL $PARAMS >/dev/null 2>&1
done
echo "용인시관광사업체 query 요청 완료"
echo ""

# 용인시신간도서 1
URL="http://4.230.159.239/gateway/apim/openapi/db/test/yonginnewbookdb"
PARAMS="page==1 size==10 $SERVICE_KEY_PARAM"
echo "=== 용인시신간도서 db 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
  echo "[$i/$ITERATIONS] 용인시신간도서 db 요청 실행 중... $URL $PARAMS"
  xh GET $URL $PARAMS >/dev/null 2>&1
done
echo "용인시신간도서 db 요청 완료"
echo ""

# 용인시신간도서 2
URL="http://4.230.159.239/gateway/apim/openapi/query/test/yonginnewbookquery"
PARAMS="$SERVICE_KEY_PARAM"
echo "=== 용인시신간도서 query 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
  echo "[$i/$ITERATIONS] 용인시신간도서 query 요청 실행 중... $URL $PARAMS"
  xh GET $URL $PARAMS >/dev/null 2>&1
done
echo "용인시신간도서 query 요청 완료"
echo ""

# 용인시신간도서 3
URL="http://4.230.159.239/gateway/apim/openapi/query/test/yonginnewbookquery"
PARAMS="$SERVICE_KEY_PARAM loan_yn==Y"
echo "=== 용인시신간도서 query loan_yn=Y 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
  echo "[$i/$ITERATIONS] 용인시신간도서 query loan_yn=Y 요청 실행 중... $URL $PARAMS"
  xh GET $URL $PARAMS >/dev/null 2>&1
done
echo "용인시신간도서 query loan_yn=Y 요청 완료"
echo ""

# 용인시신간도서 4
URL="http://4.230.159.239/gateway/apim/openapi/query/test/yonginnewbookquery"
PARAMS="$SERVICE_KEY_PARAM loan_yn==N"
echo "=== 용인시신간도서 query loan_yn=N 요청 시작 ==="
for i in $(seq 1 $ITERATIONS); do
  echo "[$i/$ITERATIONS] 용인시신간도서 query loan_yn=N 요청 실행 중... $URL $PARAMS"
  xh GET $URL $PARAMS >/dev/null 2>&1
done
echo "용인시신간도서 query loan_yn=N 요청 완료"
echo ""

echo "=== 모든 테스트 완료 ==="
