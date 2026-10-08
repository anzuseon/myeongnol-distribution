# 명놀 런처 배포 파일

명선놀이터 시즌3 전용 Helios Launcher 배포 저장소입니다.

- Minecraft 26.2
- Fabric Loader 0.19.3
- Iris 1.11.2
- Sodium 0.9.1
- Koreanify 0.1.6
- Bliss Shader 2.1.1

런처가 읽는 파일: `distribution.json`

## 모드 업데이트 배포

`publish-modpack.cmd`를 실행하면 Nebula 생성, 파일 크기/MD5 검증,
GitHub Releases 업로드, Git 커밋 및 push를 차례로 처리합니다.

- 100MiB 미만 파일은 기존 Git 저장소의 다운로드 주소를 사용합니다.
- 100MiB 이상, 2GiB 미만 파일은 같은 저장소의 Releases 첨부 파일로 배포합니다.
- 큰 파일은 로컬 원본 폴더에 보존하고 `.gitignore`에 정확한 파일 경로를 추가합니다.
  Nebula는 이 로컬 파일을 읽어 모드 ID, 버전, 크기와 MD5를 생성합니다.
- SHA256 전체 값을 사용한 `artifact-<sha256>` 태그에 업로드하여 기존 파일을
  덮어쓰지 않습니다. 같은 파일의 재실행은 기존 업로드를 검증하고 재사용합니다.
- Git의 기존 GitHub 로그인 정보를 사용하므로 별도 토큰 파일이 필요 없습니다.
- 새 PC에서 배포하려면 Releases에서 큰 파일을 원래 로컬 경로로 다운로드해야 합니다.
- Nebula만 직접 실행하면 주소가 원래 raw 주소로 돌아갑니다. 배포할 때는 항상
  `publish-modpack.cmd`를 사용하세요.

`-DryRun`은 점검만 실행합니다. `-NoPush`는 Release 업로드와 Git push를 건너뛰고
로컬 커밋을 만듭니다. 이 커밋을 직접 push하지 말고, 실제 배포할 때
`publish-modpack.cmd -Force -Bump none`을 실행하여 Release 파일부터 업로드하세요.
실패 후에도 같은 명령으로 재시도하면 버전을 추가로 올리지 않습니다.

2026-10-08 복구 배포의 클라이언트: `myeongnol-client-0.90.90-SNAPSHOT.jar`
(Client 0.90.90-SNAPSHOT, Minecraft 26.2 / Fabric 0.19.3).
SHA256: `7524BD7724BEB4FE820B167CB314B1B8A8959CE58F8483D7A74F4D193FD8BD90`.
로컬 경로: `servers/Myeongnol-26.2/fabricmods/required/myeongnol-client-0.90.90-SNAPSHOT.jar`.

서버 주소는 로컬 원본의 `servers/Myeongnol-26.2/servermeta.json` 또는
`set-server-address.ps1`로 변경한 뒤 Nebula에서 다시 생성해야 합니다.
