# һ˦ �� ԭ�� Liquid Glass ���԰�

iPhone ˫��ֱ����Ƭ��ȷ�ϸ������ӣ�������ָ������˦�����Է��Ӷ�Ӧ��Ե��ס���Զ�չ�������շ�������ͣ��ԭͼͨ�� SHA-256 У��֮���ȷ���ʹ֧��ԭͼ�����ϵͳ������

ʹ�� SwiftUI ��ϵͳ��������ǩ����ԭ�� PhotosPicker��`.glass` / `.glassProminent` ��ť�� `GlassEffectContainer`����� iOS 26���� iOS 27 ʹ��ϵͳԭ�����ʣ���ѭ��̬����ͼ�����̬Ч����û�м�����ۿ��ػ���ҳ�׿ǡ�

��Ƭͨ�� Multipeer Connectivity ���ܻỰ����ȷ�ϵ��豸֮�䷢�ͣ��������ƶ���Ƭ���񡣵�һ�潨��ͬһ Wi-Fi��Wi-Fi ������������˫�� App ����ǰ̨�Ҳ���������ϵͳ��������Ȩ�ޱ���������

## ������ǩ��

`brew install xcodegen` �� `swift test` �� `xcodegen generate` �� �� iOS 26 ����� SDK �� Xcode ִ�У�

```sh
xcodebuild build -project Flick.xcodeproj -scheme Flick -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/device CODE_SIGNING_ALLOWED=NO
python3 scripts/package_ipa.py build/device/Build/Products/Release-iphoneos/Flick.app output/Flick-0.1.0-unsigned.ipa
```

�����Ǻ���ʵ arm64 iPhoneOS ��ִ���ļ���δǩ�� IPA���û�ʹ���ֻ������е�֤��ֱ���ǩ��װ������Ҫ��˽Կ�ϴ����˲ֿ⡣

## ˫������

1. ��̨�ֻ��ֱ���ǩ��װͬһ IPA�����򿪡�һ˦����
2. �����ӣ������������硣�ҵ��Է��豸���˶������룬������һ̨�������ӣ���һ̨���������ӡ�
3. ���ͷ����öԷ�����໹���Ҳࡣѡ��ϵͳ��Ƭ���е�һ��ͼƬ����ס��Ƭ��ָ������˦������㷢�Ͱ�ť��
4. ���շ�����볡��Ե���Զ��Ŵ�ԭͼ����ȷ�ϡ��ɴ�������ϵͳ������
5. ��֤��ͣ���ա����ϻص��������϶����������Ժ��е���̨���������������ɲ�����ԭͼ�ʹ

��һ�治�Զ�ʶ����ʵ�ռ�λ�ã����ҹ�ϵ���û����á�֧����ͨ��̬��Ƭԭͼ�������� Live Photo �İ�����Ƶ����ǰû����̨ʵ�� iPhone ������֤�ݣ����ܰ��豸���������������Ϊ�������ɹ���
