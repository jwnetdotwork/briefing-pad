import Foundation

struct NotionBlockList: Decodable {
    let results: [NotionBlock]
}

struct NotionBlock: Decodable {
    let id: String
    let type: String
    let heading_2: NotionHeading?
    let heading_3: NotionHeading?
    let heading_4: NotionHeading?
    let paragraph: NotionTextContent?
    let bulleted_list_item: NotionTextContent?
    let image: NotionImage?

    enum CodingKeys: String, CodingKey {
        case id, type, heading_2, heading_3, heading_4, paragraph, bulleted_list_item, image
    }
}

struct NotionHeading: Decodable {
    let rich_text: [NotionRichText]
}

struct NotionTextContent: Decodable {
    let rich_text: [NotionRichText]
}

struct NotionRichText: Decodable {
    let plain_text: String
}

struct NotionImage: Decodable {
    let caption: [NotionRichText]
    let type: String
    let external: NotionExternal?
    let file: NotionFile?
}

struct NotionExternal: Decodable {
    let url: String
}

struct NotionFile: Decodable {
    let url: String
}
