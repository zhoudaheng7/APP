import UIKit
import CoreText

enum StoryPDF {
    static func render(_ story: StoryRecord) throws -> Data {
        try story.validate()
        let page = CGRect(x:0,y:0,width:595,height:842), margin: CGFloat = 48
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String:story.title,kCGPDFContextAuthor as String:"朝屿 Dayisle",kCGPDFContextCreator as String:"Dayisle Story v1"]
        let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 7; paragraph.paragraphSpacing = 12
        let text = NSMutableAttributedString(string:story.title + "\n",attributes:[.font:UIFont.systemFont(ofSize:26,weight:.semibold),.foregroundColor:UIColor.black,.paragraphStyle:paragraph])
        text.append(NSAttributedString(string:"私人故事 · 第\(story.version)版\n\n",attributes:[.font:UIFont.systemFont(ofSize:11),.foregroundColor:UIColor.darkGray,.paragraphStyle:paragraph]))
        let normal: [NSAttributedString.Key:Any] = [.font:UIFont.systemFont(ofSize:12),.foregroundColor:UIColor.black,.paragraphStyle:paragraph]
        if !story.narrative.isEmpty { text.append(NSAttributedString(string:story.narrative + "\n\n",attributes:normal)) }
        for section in story.sections {
            text.append(NSAttributedString(string:section.title + "\n",attributes:[.font:UIFont.systemFont(ofSize:16,weight:.semibold),.foregroundColor:UIColor.black,.paragraphStyle:paragraph]))
            text.append(NSAttributedString(string:section.text + "\n\n",attributes:normal))
        }
        text.append(NSAttributedString(string:"内容来自本人所选记录及手写文字。未推断活动、成果或未记录的经历。照片中的人物、地标与原文中的其他隐私，请在分享前自行核对。",attributes:[.font:UIFont.systemFont(ofSize:10),.foregroundColor:UIColor.darkGray,.paragraphStyle:paragraph]))
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let renderer = UIGraphicsPDFRenderer(bounds:page,format:format)
        var pageCount = 0
        var complete = false
        let bytes = renderer.pdfData { context in
            func beginPage() {
                context.beginPage(); pageCount += 1
                UIColor.white.setFill(); context.cgContext.fill(page)
                let footer = "朝屿 Dayisle  ·  \(pageCount)"
                (footer as NSString).draw(at:CGPoint(x:margin,y:page.height - 32),withAttributes:[.font:UIFont.systemFont(ofSize:9),.foregroundColor:UIColor.gray])
            }
            var position = 0
            while position < text.length && pageCount < 80 {
                beginPage()
                let cg = context.cgContext; cg.saveGState(); cg.translateBy(x:0,y:page.height); cg.scaleBy(x:1,y:-1)
                let path = CGPath(rect:CGRect(x:margin,y:margin + 10,width:page.width - 2 * margin,height:page.height - 2 * margin - 28),transform:nil)
                let frame = CTFramesetterCreateFrame(framesetter,CFRange(location:position,length:0),path,nil)
                CTFrameDraw(frame,cg); let range = CTFrameGetVisibleStringRange(frame); cg.restoreGState()
                guard range.length > 0 else { break }; position += range.length
            }
            complete = position == text.length
            // One photo per page avoids clipping and preserves a quiet, readable layout.
            for photo in story.photos {
                guard let image = UIImage(data:photo.jpeg) else { continue }
                beginPage(); let bounds = CGRect(x:margin,y:margin,width:page.width - 2 * margin,height:page.height - 2 * margin - 90)
                let scale = min(bounds.width / image.size.width,bounds.height / image.size.height)
                let size = CGSize(width:image.size.width * scale,height:image.size.height * scale)
                image.draw(in:CGRect(x:bounds.midX - size.width / 2,y:bounds.midY - size.height / 2,width:size.width,height:size.height))
                (photo.caption as NSString).draw(in:CGRect(x:margin,y:page.height - margin - 75,width:bounds.width,height:45),withAttributes:normal)
            }
        }
        guard complete,pageCount < 80,bytes.count <= 20 * 1024 * 1024 else { throw LifeError.message("故事过长，未生成不完整PDF，请减少内容。") }
        return bytes
    }
}
