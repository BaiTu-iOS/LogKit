// Created by yuxilong on 2026/10/22.

import LogKit
import Testing

/// 编译期覆盖同名属性查找、enum、actor 和泛型的实际语言约束。
struct LogCompilationTests {
    @Logger("Catalog")
    private final class Service {
        func instanceModule() -> String {
            log.category
        }

        static func typeModule() -> String {
            log.category
        }
    }

    @Logger("Catalog")
    private enum Fetch {
        static func module() -> String {
            log.category
        }
    }

    @Logger("Catalog")
    private actor Worker {
        func instanceModule() -> String {
            log.category
        }

        static func typeModule() -> String {
            log.category
        }
    }

    @Logger("Catalog")
    private struct GenericService<Value> {
        func module() -> String {
            log.category
        }

        @Logger("Catalog")
        struct Inner {
            func module() -> String {
                log.category
            }
        }
    }

    @Logger("Catalog")
    private enum GenericFetch<Value> {}

    @Test
    func `resolves both member scopes`() {
        #expect(Service().instanceModule() == "Catalog")
        #expect(Service.typeModule() == "Catalog")
        #expect(Fetch.module() == "Catalog")
        #expect(GenericService<Int>().module() == "Catalog")
        #expect(GenericService<Int>.Inner().module() == "Catalog")
        #expect(ExtendedService<Int>.Inner().module() == "Catalog")
    }

    @Test
    func `resolves actor member scopes`() async {
        #expect(await Worker().instanceModule() == "Catalog")
        #expect(Worker.typeModule() == "Catalog")
    }
}

/// 扩展不携带原始声明的泛型参数，宏需保守跳过其中的静态存储属性。
private struct ExtendedService<Value> {}

extension ExtendedService {
    @Logger("Catalog")
    struct Inner {
        func module() -> String {
            log.category
        }
    }
}
