# 명놀 런처 배경 관리

런처 1.0.9부터 appearance.json의 배경을 자동으로 표시합니다. 런처 시작 시, 실행 중 5분마다, 창을 다시 활성화할 때 확인합니다. GitHub 전파 지연이 있으면 다음 확인에 반영될 수 있습니다.

## 배경 변경

```powershell
& C:\MyeongnolDistribution\set-launcher-background.ps1 -ImagePath "C:\배경\새배경.png"
```

20MiB 이하 PNG·JPEG·WebP를 지정합니다. 스크립트가 해시 이름의 이미지와 SHA256 설정을 커밋하고 GitHub에 올립니다. 같은 이미지는 재사용하며 이전 배경은 보존합니다. 이전 파일을 지정하면 되돌릴 수 있습니다. -NoPush는 로컬 커밋까지만 만듭니다.

이 작업은 distribution.json이나 게임·모드팩 버전을 변경하지 않습니다. Nebula를 실행하지 않아도 됩니다.

## 직접 관리

appearance.json의 schemaVersion은 1입니다. background.url에 HTTPS 이미지 주소를, background.sha256에 해당 파일의 소문자 SHA256을 지정합니다. 이미지를 바꾸면 두 값을 함께 갱신합니다. 외부 HTTPS 이미지 서버 주소도 사용할 수 있습니다.

런처는 크기·형식·SHA256·디코딩 검증을 통과한 배경만 적용합니다. 연결이 끊기거나 설정이 잘못되면 마지막 정상 배경을 유지하고, 캐시가 없으면 기본 전투 일러스트를 표시합니다.
